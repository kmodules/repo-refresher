#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=kmodules-repo-refresher # -$(date +%s)
COMMIT_MSG="Fix satori/go.uuid security vulnerability"

REPO_ROOT=/tmp/kmodules-repo-refresher

KMODULES_CLIENT_GO=${KMODULES_CLIENT_GO:-1fbfd52e78c9016d9c7b25067a51ed80f55b3ebc}
KMODULES_MONITORING_AGENT_API=${KMODULES_MONITORING_AGENT_API:-38ca075a2dbde85cf48d84b699720925066a5f3a}
KMODULES_WEBHOOK_RUNTIME=${KMODULES_WEBHOOK_RUNTIME:-7f73c2ab318a43feb61f11696815d2abdc745af1}
KMODULES_RESOURCE_METADATA=${KMODULES_RESOURCE_METADATA:-v0.6.4}
KMODULES_CUSTOM_RESOURCES=${KMODULES_CUSTOM_RESOURCES:-72bd9e8cae6e8ca708e6e716bef12a2f58f60b96}
KMODULES_OBJECTSTORE_API=${KMODULES_OBJECTSTORE_API:-fdf68f88ea6e6b92a3c31339128b3551e2bc9742}

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 https://${GITHUB_USER}:${GITHUB_TOKEN}@$1.git
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    if [ -f go.mod ]; then
        if [ "$1" != "github.com/kmodules/client-go" ]; then
            go mod edit \
                -require kmodules.xyz/client-go@${KMODULES_CLIENT_GO}
            go mod tidy
        fi
        # if [ "$1" != "github.com/kmodules/monitoring-agent-api" ]; then
        #     go mod edit \
        #         -require kmodules.xyz/monitoring-agent-api@${KMODULES_MONITORING_AGENT_API}
        #     go mod tidy
        # fi
        # if [ "$1" != "github.com/kmodules/webhook-runtime" ]; then
        #     go mod edit \
        #         -require kmodules.xyz/webhook-runtime@${KMODULES_WEBHOOK_RUNTIME}
        #     go mod tidy
        # fi
        # if [ "$1" != "github.com/kmodules/resource-metadata" ]; then
        #     go mod edit \
        #         -require kmodules.xyz/resource-metadata@${KMODULES_RESOURCE_METADATA}
        #     go mod tidy
        # fi
        # if [ "$1" != "github.com/kmodules/custom-resources" ]; then
        #     go mod edit \
        #         -require kmodules.xyz/custom-resources@${KMODULES_CUSTOM_RESOURCES}
        #     go mod tidy
        # fi
        # if [ "$1" != "github.com/kmodules/objectstore-api" ]; then
        #     go mod edit \
        #         -require kmodules.xyz/objectstore-api@${KMODULES_OBJECTSTORE_API}
        #     go mod tidy
        # fi
        go mod edit \
            -require=go.bytebuilders.dev/license-verifier@v0.9.3 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.9.3 \
            -require=go.bytebuilders.dev/audit@v0.0.10 \
            -require=gomodules.xyz/x@v0.0.8 \
            -replace=github.com/satori/go.uuid=github.com/gomodules/uuid@v4.0.0+incompatible \
            -replace=github.com/dgrijalva/jwt-go=github.com/gomodules/jwt@v3.2.2+incompatible \
            -replace=github.com/golang-jwt/jwt=github.com/golang-jwt/jwt@v3.2.2+incompatible \
            -replace=github.com/form3tech-oss/jwt-go=github.com/form3tech-oss/jwt-go@v3.2.5+incompatible \
            -replace=helm.sh/helm/v3=github.com/kubepack/helm/v3@v3.6.1-0.20210518225915-c3e0ce48dd1b \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.21.2-0.20210716212718-83e5493ac170
        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # run an extra make fmt because when make gen fails, make fmt is not run
        make fmt || true
    )
    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin $PR_BRANCH -f
        hub pull-request \
            --labels automerge \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1
