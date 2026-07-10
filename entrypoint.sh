#!/bin/bash

set -o pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
suffix=${SUFFIX:-master}
verbose=${VERBOSE:-true}
git_api_tagging=${GIT_API_TAGGING:-true}
tag_message=${TAG_MESSAGE:-""}
major_string_token=${MAJOR_STRING_TOKEN:-#major}
minor_string_token=${MINOR_STRING_TOKEN:-#minor}
patch_string_token=${PATCH_STRING_TOKEN:-#patch}
none_string_token=${NONE_STRING_TOKEN:-#none}
branch_history=${BRANCH_HISTORY:-compare}
default_branch=${DEFAULT_BRANCH:-$GITHUB_BASE_REF}

# since https://github.blog/2022-04-12-git-security-vulnerability-announced/ the runner
# workspace is owned by a different user than the action container; mark it safe
git config --global --add safe.directory /github/workspace

cd ${GITHUB_WORKSPACE}/${source}

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tSUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"
echo -e "\tGIT_API_TAGGING: ${git_api_tagging}"
echo -e "\tTAG_MESSAGE: ${tag_message}"
echo -e "\tMAJOR_STRING_TOKEN: ${major_string_token}"
echo -e "\tMINOR_STRING_TOKEN: ${minor_string_token}"
echo -e "\tPATCH_STRING_TOKEN: ${patch_string_token}"
echo -e "\tNONE_STRING_TOKEN: ${none_string_token}"
echo -e "\tBRANCH_HISTORY: ${branch_history}"
echo -e "\tDEFAULT_BRANCH: ${default_branch}"

current_branch=$(git rev-parse --abbrev-ref HEAD)

# fetch tags
git fetch --tags

# get latest tag that looks like a semver (with or without v), carrying our suffix
tagFmt="^v?[0-9]+\.[0-9]+\.[0-9]+(-$suffix)$"

# collect the git refs once, based on context
git_refs=
case "$tag_context" in
    *repo*)
        git_refs=$(git for-each-ref --sort=-v:refname --format '%(refname:lstrip=2)')
        ;;
    *branch*)
        git_refs=$(git tag --list --merged HEAD --sort=-v:refname)
        ;;
    * ) echo "Unrecognised context"; exit 1;;
esac

# grep with '|| true' so a no-match (exit 1) doesn't trip pipefail; head reads from a
# here-string, not a pipe, so the previous 'grep | head' SIGPIPE hazard is gone
matching_tag_refs=$( (grep -E "$tagFmt" <<< "$git_refs") || true)
tag=$(head -n 1 <<< "$matching_tag_refs")
pre_tag="$tag"

echo "tag: $tag, pre_tag: $pre_tag"

# if there are none, start tags at INITIAL_VERSION which defaults to 0.0.0
if [ -z "$tag" ]
then
    tag="$initial_version"
    pre_tag="$initial_version"
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 "$tag" || true)

# get current commit hash
commit=$(git rev-parse HEAD)

echo "tag_commit: $tag_commit, commit: $commit"

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo old_tag=$tag >> $GITHUB_OUTPUT
    echo tag=$tag >> $GITHUB_OUTPUT
    exit 0
fi

# BRANCH_HISTORY=full diffs against the default branch, so make sure we have one
if [ "$branch_history" == "full" ] && [ -z "$default_branch" ]
then
    default_branch=$(git branch -rl '*/master' '*/main' | cut -d / -f2)
    if [ -z "$default_branch" ]
    then
        echo "::error::BRANCH_HISTORY=full requires DEFAULT_BRANCH to be set."
        exit 1
    fi
fi

# choose which commit messages to scan for #bump tokens
if [ -z "$tag_commit" ]
then
    # no previous tag exists — scan the whole history
    log=$(git log --pretty='%B')
else
    case "$branch_history" in
        last)    log=$(git show -s --format='%B') ;;
        full)    log=$(git log ${default_branch}..HEAD --pretty='%B') ;;
        compare) log=$(git log $tag..HEAD --pretty='%B') ;;
        * ) echo "Unrecognised BRANCH_HISTORY: $branch_history"; exit 1 ;;
    esac
fi

echo "log: $log"


case "$log" in
    *$major_string_token* ) new=$(semver -i major $(echo $tag | sed "s/-$suffix//g")); part="major";;
    *$minor_string_token* ) new=$(semver -i minor $(echo $tag | sed "s/-$suffix//g")); part="minor";;
    *$patch_string_token* ) new=$(semver -i patch $(echo $tag | sed "s/-$suffix//g")); part="patch";;
    *$none_string_token* )
        echo "Default bump was set to none. Skipping..."; echo old_tag=$tag >> $GITHUB_OUTPUT; echo new_tag=$tag >> $GITHUB_OUTPUT; echo tag=$tag >> $GITHUB_OUTPUT; exit 0;;
    * )
        if [ "$default_semvar_bump" == "none" ]; then
            echo "Default bump was set to none. Skipping..."; echo old_tag=$tag >> $GITHUB_OUTPUT; echo new_tag=$tag >> $GITHUB_OUTPUT; echo tag=$tag >> $GITHUB_OUTPUT; exit 0
        else
            new=$(semver -i "${default_semvar_bump}" $(echo $tag | sed "s/-$suffix//g")); part=$default_semvar_bump
        fi
        ;;
esac
new=$new-$suffix

# did we get a new tag?
if [ ! -z "$new" ]
then
	# prefix with 'v'
	if $with_v
	then
		new="v$new"
	fi
fi

if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

echo -e "Bumping tag ${tag}. \n\tNew tag ${new}"

# set outputs
echo new_tag=$new >> $GITHUB_OUTPUT
echo part=$part >> $GITHUB_OUTPUT
echo old_tag=$tag >> $GITHUB_OUTPUT

# use dry run to determine the next tag
if $dryrun
then
    echo tag=$tag >> $GITHUB_OUTPUT
    exit 0
fi 

echo tag=$new >> $GITHUB_OUTPUT

# create local git tag; annotated when a message is supplied, else lightweight
# NOTE: annotations only survive when pushed via git (GIT_API_TAGGING=false); the refs
# API path below recreates a lightweight tag from the commit SHA and drops the message.
if [ -n "$tag_message" ]
then
    echo "EVENT: creating annotated local tag $new with message: $tag_message"
    git tag -a "$new" -m "$tag_message"
else
    echo "EVENT: creating local tag $new"
    git tag -f "$new"
fi

echo 'Debug:'
echo "$new: ${new}"
echo "$GITHUB_REPOSITORY: ${GITHUB_REPOSITORY}"
echo "$GITHUB_EVENT_PATH: ${GITHUB_EVENT_PATH}"

ls -lah .

if $git_api_tagging
then
    # push new tag ref via the github refs API
    dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
    full_name=$GITHUB_REPOSITORY
    git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

    echo "$dt: **pushing tag $new to repo $full_name"

    git_refs_response=$(
    curl -s -X POST $git_refs_url \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
)

    git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

    echo "::debug::${git_refs_response}"
    if [ "${git_ref_posted}" = "refs/tags/${new}" ]; then
      exit 0
    else
      echo "::error::Tag was not created properly."
      exit 1
    fi
else
    # push new tag via the git cli (preserves annotated tags)
    echo "**pushing tag $new to origin"
    git push -f origin "$new" || exit 1
fi
