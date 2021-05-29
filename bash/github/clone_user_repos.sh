#!/usr/bin/env bash

# Read secrets such as GITHUB_API_TOKEN
if [[ -f "${HOME}/.secrets.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.secrets.sh"
fi

# Get the github username - assumes first parameter is the username
if [[ -z "${1}" ]] && [[ -z "${GITHUB_USERNAME}" ]]; then
    echo -e "Usage: $(basename "${0}") <github username>"
    echo -e "    You may also set the environment variable GITHUB_USERNAME"
    exit 1
fi

# Override environment variable with script argument
if [[ -n "${1}" ]]; then
    GITHUB_USERNAME="${1}"
fi

# Setup ssh (for git clone)
eval "$(ssh-agent -s)"
ssh-add "${HOME}/.ssh/id_rsa"

echo "${GITHUB_USERNAME}"
mkdir -p "${GITHUB_USERNAME}"
PAGE=0
REPOS=$(curl -s -H "Authorization: token ${GITHUB_API_TOKEN}" "https://api.github.com/search/repositories?q=user:${GITHUB_USERNAME}&page=${PAGE}&per_page=100" | jq -r '.items[] | .name,.ssh_url')
while [ "${#REPOS}" -gt "0" ]; do
    while read -r REPO && read -r SSH_URL; do
        echo "${REPO} -- ${SSH_URL}"
        (cd "${GITHUB_USERNAME}" || exit 1; [[ -d "${REPO}" ]] || git clone "${SSH_URL}")
    done <<< "${REPOS}"
    ((PAGE++))
    REPOS=$(curl -s -H "Authorization: token ${GITHUB_API_TOKEN}" "https://api.github.com/search/repositories?q=user:${GITHUB_USERNAME}&page=${PAGE}&per_page=100" | jq -r '.items[] | .name,.ssh_url')
done
