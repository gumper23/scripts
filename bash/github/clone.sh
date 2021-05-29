#!/usr/bin/env bash

if [ -z "${GITHUB_API_TOKEN}" ]; then
    echo "Please set environment variable GITHUB_API_TOKEN to a valid GHE API token"
    exit 1
fi

# For each user's organizations
for ORG in $(curl -H "Authorization: token ${GITHUB_API_TOKEN}" https://api.github.com/user/orgs -G -s | jq -r '.[] | .login'); 
do
    echo "${ORG}"
    mkdir -p "${ORG}"

    # Loop through every REPO
    (cd "${ORG}" || exit;
     PAGE=0;
     REPOS=$(curl -H "Authorization: token ${GITHUB_API_TOKEN}" -Gs -d per_page=100 -d page="${PAGE}" "https://api.github.com/orgs/${ORG}/repos" | jq -r '.[] | .name,.ssh_url | @text');
     while [ "${#REPOS}" -gt "0" ]; 
     do
         # Clone the REPO
         while read -r REPO && read -r SSH_URL; 
         do
             echo "${ORG} --- ${REPO} --- ${SSH_URL}";
             REPO_PATH="${PWD}/${REPO}";
             [[ -d "${REPO_PATH}" ]] && continue;
             git clone "${SSH_URL}";
         done <<< "${REPOS}";
         PAGE=$((PAGE+1));
	 REPOS=$(curl -H "Authorization: token ${GITHUB_API_TOKEN}" -Gs -d per_page=100 -d page="${PAGE}" "https://api.github.com/orgs/${ORG}/repos" | jq -r '.[] | .name,.ssh_url | @text');
     done;
    );
done;
