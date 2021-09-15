#!/usr/bin/env bash
# echo all the commands 
set -x 
PRSUFFIX=develop
REPOORG=splunk

command -v gh >/dev/null 2>&1 || { echo >&2 "I require gh but it's not installed.  Aborting."; exit 1; }
command -v git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }
command -v crudini >/dev/null 2>&1 || { echo >&2 "I require crudini but it's not installed.  Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo >&2 "I require rsync but it's not installed.  Aborting."; exit 1; }

echo "Working on:$REPO|$TAID|$REPOVISIBILITY|$TITLE|$BRANCH|$OTHER"
#Things we want to do no matter what
#Conditional work
if ! gh repo view $REPOORG/${REPO} >/dev/null
then
    rm -rf work/$REPO
    echo Repository is new
    mkdir -p work/$REPO || true
    pushd work/$REPO || exit 1
    
    rsync -avh --include ".*" ../../seed/ .
    rsync -avh --include ".*" ../../enforce/ .

    crudini --set package/default/app.conf launcher description "$TITLE"
    crudini --set package/default/app.conf ui label "$TITLE"
    crudini --set package/default/app.conf package id $TAID
    crudini --set package/default/app.conf id name $TAID

    tmpf=$(mktemp)
    jq --arg TITLE "${TITLE}" '.info.title = $TITLE' package/app.manifest >$tmpf
    mv -f $tmpf package/app.manifest
    tmpf=$(mktemp)
    jq --arg TITLE "${TITLE}" '.info.description = $TITLE' package/app.manifest >$tmpf
    mv -f $tmpf package/app.manifest
    jq --arg TAID "${TAID}" '.info.id.name = $TAID' package/app.manifest >$tmpf
    mv -f $tmpf package/app.manifest

    poetry init -n --author "Splunk Inc, <sales@splunk.com>" --python "^3.7" -l "Splunk-1-2020"
    reuse add pyproject.toml
    poetry add --lock --dev splunk-add-on-ucc-framework
    poetry add --lock --dev lovely-pytest-docker
    poetry add --lock --dev reuse
    poetry add --lock --dev pytest
    poetry add --lock --dev splunk-packaging-toolkit
    poetry add --lock --dev pytest-xdist
    poetry add --lock --dev pytest-splunk-addon
    poetry add --lock --dev pytest-expect
    poetry add --lock --dev pytest-splunk-addon-ui-smartx
    poetry add --lock --dev pytest-rerunfailures
    poetry add --lock --dev coverage
    poetry add --lock --dev pytest-cov
    
    git init
    git config  user.email "addonfactory@splunk.com"
    git config  user.name "Addon Factory template"
    git submodule add git@github.com:$REPOORG/addonfactory-splunk_sa_cim.git deps/apps/Splunk_SA_CIM
    
    git add .
    git commit -am "base"
    git tag -a v0.2.0 -m "CI base"

    gh create -p $REPOORG/$REPO
    gh api orgs/$REPOORG/teams/products-shared-services-all/repos/$REPOORG/$REPO --raw-field 'permission=maintain' -X PUT
    gh api orgs/$REPOORG/teams/productsecurity/repos/$REPOORG/$REPO --raw-field 'permission=read' -X PUT
    gh api orgs/$REPOORG/teams/products-gdi-addons/repos/$REPOORG/$REPO --raw-field 'permission=maintain' -X PUT
    gh api orgs/$REPOORG/teams/products-gdi-addons-adminrepo/repos/$REPOORG/$REPO --raw-field 'permission=admin' -X PUT
    gh api orgs/$REPOORG/$REPO -X PATCH --field default_branch=main
    gh api /repos/$REPOORG/$REPO --raw-field 'visibility=${REPOVISIBILITY}' -X PATCH
    gh api /repos/$REPOORG/$REPO  -H 'Accept: application/vnd.github.nebula-preview+json' -X PATCH -F visibility=$REPOVISIBILITY

else
    echo Repository is existing

    gh api repos/$REPOORG/$REPO --raw-field 'visibility=${REPOVISIBILITY}' -X PATCH || true
    
    echo "adding permission for teams"
    gh api orgs/$REPOORG/teams/products-gdi-addons/repos/$REPOORG/$REPO --raw-field 'permission=maintain' -X PUT
    gh api orgs/$REPOORG/teams/products-gdi-addons-adminrepo/repos/$REPOORG/$REPO --raw-field 'permission=admin' -X PUT

    if [ ! -d "work/$REPO" ]; then
        #hub clone $REPOORG/$REPO work/$REPO
        git clone https://${GH_USER_ADMIN}:${GH_TOKEN_ADMIN}@github.com/$REPOORG/$REPO.git work/$REPO || exit 1
        pushd work/$REPO || exit 1
        git checkout main || exit 1
    else
        pushd work/$REPO || exit 1
        git fetch
        git checkout main || exit 1
        git pull || exit 1
    fi
    git remote set-url origin https://${GH_USER_ADMIN}:${GH_TOKEN_ADMIN}@github.com/$REPOORG/$REPO.git

    gh api /repos/$REPOORG/$REPO  -H 'Accept: application/vnd.github.nebula-preview+json' -X PATCH -F visibility=$REPOVISIBILITY
    git push -d origin test/common-template-rollout-changes-refs/heads/develop
fi
popd
