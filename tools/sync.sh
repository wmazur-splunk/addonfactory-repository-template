#!/usr/bin/env bash
# echo all the commands 
set -x 
PRSUFFIX=develop
REPOORG=splunk
CHANGE_BRANCH="test/$(git rev-parse --abbrev-ref HEAD)"
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
    
    git add .
    git commit -am "base"
    git tag -a v0.2.0 -m "CI base"

    gh repo create -p $REPOORG/$REPO
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

    ( git checkout test/common-template-wfe-rollout-changes && git checkout main && git branch -D test/common-template-wfe-rollout-changes) || true
    git checkout -B "test/common-template-wfe-rollout-changes" main
    git submodule update --init --recursive

    rsync -avh --include ".*" --ignore-existing ../../seed/ .
    rsync -avh --include ".*" ../../enforce/ .

    #Cleanup of bad module
    # Remove the submodule entry from .git/config
    git submodule deinit -f deps/script || true
    # Remove the submodule directory from the superproject's .git/modules directory
    rm -rf .git/modules/deps/script || true

    # Remove the entry in .gitmodules and remove the submodule directory located at path/to/submodule
    git rm -f deps/script || true
    #Updates for pytest-splunk-add-on >=1.2.2a1
    if [ ! -d "tests/data" ]; then
        mkdir -p tests/data
    fi
    if [ -f "tests/data/wordlist.txt" ]; then
        git rm tests/data/wordlist.txt
    fi
    if [ -f "package/default/eventgen.conf" ]; then
        git mv package/default/eventgen.conf tests/data/eventgen.conf
    fi
    if [ -d "package/samples" ]; then
        git mv package/samples tests/data/samples
    fi
    if [ -d ".dependabot" ]; then
        git rm -rf .dependabot
    fi
    if [ -d "deps/apps/splunk_env_indexer" ]; then
        git submodule deinit -f deps/apps/splunk_env_indexer
        rm -rf .git/modules/deps/apps/splunk_env_indexer
        git rm -f deps/apps/splunk_env_indexer
        git add deps/apps/splunk_env_indexer
        git commit -m "Deprecate splunk_env_indexer submodule"
    fi       
    if [ -d "deps/build/addonfactory_test_matrix_splunk" ]; then
        git submodule deinit -f deps/build/addonfactory_test_matrix_splunk
        rm -rf .git/modules/deps/build/addonfactory_test_matrix_splunk
        git rm -f deps/build/addonfactory_test_matrix_splunk
        git add deps/build/addonfactory_test_matrix_splunk
        git commit -m "Deprecate deps/build/addonfactory_test_matrix_splunk submodule"
    fi       

    if [[ -f "requirements.txt" ]]; then
        mkdir -p package/lib || true
        git mv requirements.txt package/lib/
    fi
    if [[ -f "requirements_py2.txt" ]]; then
        mkdir -p package/lib/py2 || true
        git mv requirements.txt package/lib/py2/
    fi        
    if [[ -f "requirements_py3.txt" ]]; then
        mkdir -p package/lib/py3 || true
        git mv requirements.txt package/lib/py3/
    fi
    if [[ -f "splver.py" ]]; then
        git rm splver.py
    fi
    if [[ -f "packagingScript.sh" ]]; then
        git rm packagingScript.sh          
    fi
    git rm splunk_add_on_ucc_framework-* || true        
    if [[ -f "build.sh" ]]; then
        git rm build.sh          
    fi
    if [ -d "deps/build/disable_popup" ]; then
        git rm -f deps/build/disable_popup
        git submodule update --remote --merge deps/build/addonfactory_test_matrix_splunk
        git add deps/build/disable_popup
        git commit -m "Deprecate disable_popup"
    fi
    if [[ -d "tests/data" ]]; then
        mkdir -p tests/knowledge || true
        git mv tests/data/* tests/knowledge
    fi
    if [[ -f "tests/knowledge/requirements.txt" ]]; then
        git rm tests/knowledge/requirements.txt || true
    fi
    if [[ -f "tests/knowledge/wordlist.txt" ]]; then
        git rm tests/knowledge/wordlist.txt || true
    fi
    if [[ -f "tests/ui/requirements.txt" ]]; then
        git rm tests/ui/requirements.txt || true
    fi     
    if [[ -f "tests/pytest.ini" ]]; then
        git rm tests/pytest.ini || true
    fi
    if [[ -f "tests/test_addon.py" ]]; then
        git rm tests/test_addon.py || true
    fi
    if [[ -f "tests/__init__.py" ]]; then
        git rm tests/__init__.py || true
    fi
    if [[ -f "tests/pytest-ci.ini" ]]; then
        git rm tests/pytest-ci.ini || true
    fi
    if [[ -f "tests/conftest.py" ]]; then
        git rm tests/conftest.py || true
    fi
    if [[ -f "tests/requirements.txt" ]]; then
        git rm tests/requirements.txt || true
    fi
    if [[ -f "requirements.txt" ]]; then
        git rm requirements.txt || true
    fi
    if [[ -f ".python-version" ]]; then
        git rm .python-version || true
    fi
    if [[ -f ".github/workflows/cla.yaml" ]]; then
        git rm .github/workflows/cla.yaml || true
    fi
    if [[ -f "tests/backend_entrypoint.sh" ]]; then
        git rm tests/backend_entrypoint.sh || true
    fi        
    if [[ -d "tests/ui" ]]; then
        rsync -avh --include ".*" ../../conditional/ .
    fi
    if [[ -f ".github/workflows/reuse.yml" ]]; then
        git rm .github/workflows/reuse.yml || true
    fi        
    if [[ -f ".github/workflows/snyk.yaml" ]]; then
        git rm .github/workflows/snyk.yaml || true
    fi        
    if [[ -f ".github/workflows/rebase.yml" ]]; then
        git rm .github/workflows/rebase.yml || true
    fi        
    if [[ -f ".releaserc.yaml" ]]; then
        git rm .releaserc.yaml || true
    fi        
    if [[ -f "NOTICE" ]]; then
        git rm NOTICE || true
    fi 
    if [[ -f "package/lib/py2/requirements.txt" ]]; then
        git rm package/lib/py2/requirements.txt || true
    fi  
    if [[ -f "package/lib/py2/requirements.txt" ]]; then
        git rm package/lib/py2/requirements.txt || true
    fi  
    if [[ -f "requirements_py2_dev.txt" ]]; then
        git rm requirements_py2_dev.txt || true
    fi
    
    if [[ ! -f "pyproject.toml" ]]; 
    then 
        poetry init -n --author "Splunk Inc, <sales@splunk.com>" --python "^3.7" -l "Splunk-1-2020"
        reuse add pyproject.toml
        if [[ -f "package/lib/requirements.txt" ]]; then
            cat package/lib/requirements.txt | grep -v '^#' | grep -v '^\s*$' | grep -v '^six' | grep -v 'future' | xargs poetry add
            cat package/lib/requirements.txt | grep -v '^#' | grep -v '^\s*$' | grep '^six\|^future' | cut -d= -f1 | xargs poetry add --lock  
            git rm package/lib/requirements.txt || true
        fi
        if [[ -f "package/lib/py3/requirements.txt" ]]; then
            cat package/lib/py3/requirements.txt | grep -v '^#' | grep -v '^\s*$' | grep -v '^six' | grep -v 'future' | xargs poetry add
            cat package/lib/py3/requirements.txt | grep -v '^#' | grep -v '^\s*$' | grep '^six\|^future' | cut -d= -f1 | xargs poetry add --lock  
            git rm package/lib/py3/requirements.txt || true
        fi
        if [[ -f "requirements_addon_specific.txt" ]]; then
            current=$(poetry show -t | grep '^[a-z]' | sed 's| .*||g' | paste -s -d\| - | sed 's/\|/\\\|/g')
            new=($(cat requirements_addon_specific.txt \
                | grep -v '^#' | grep -v '^\s*$' | grep -v '^six' | grep -v 'future' \
                | grep -v ${current}))
            for i in "${new[@]}"
            do
            : 
                poetry add --lock $i --dev || echo \# $i>>requirements_broken.txt
            done
        fi
        if [[ -f "requirements_dev.txt" ]]; then
            current=$(poetry show -t | grep '^[a-z]' | sed 's| .*||g' | paste -s -d\| - | sed 's/\|/\\\|/g')
            new=($(cat requirements_dev.txt \
                | grep -v 'splunk-packaging-toolkit' \
                | grep -v '^#' | grep -v '^\s*$' | grep -v '^six' | grep -v 'future' | grep -v '^-r' \
                | grep -v "^\(${current}\)\(==\| *$\)"))
            for i in "${new[@]}"
            do
            : 
                poetry add --lock $i --dev || echo \# $i>>requirements_broken.txt
            done
            cat requirements_dev.txt | grep -v '^#' | grep -v '^\s*$' | grep '^six\|^future' | cut -d= -f1 | xargs -I{} poetry add --lock {}==* --dev
            git rm requirements_dev.txt || true
        fi
        current=$(poetry show -t | grep '^[a-z]' | sed 's| .*||g' | paste -s -d\| - | sed 's/\|/\\\|/g')
        poetry add --lock splunk-packaging-toolkit --dev  || true
        poetry add --lock pytest-splunk-addon --dev  || true
        
        if [[ -d tests/ui ]]; then
            poetry add --lock -D pytest-splunk-addon-ui-smartx pytest-splunk-addon splunk-add-on-ucc-framework || true
        else
            poetry remove pytest-splunk-addon-ui-smartx  --dev || true
            poetry add --lock -D pytest-splunk-addon splunk-add-on-ucc-framework || true
        fi
        if [[ -d tests/unit ]]; then
            poetry add --lock pytest-cov --dev  || true
            poetry add --lock coverage --dev  || true
        else 
            poetry remove coverage  --dev || true
            poetry remove pytest-cov  --dev || true
        fi
        poetry remove configparser || true

        if [[ -f "requirements_addon_specific.txt" ]]; then
            cat requirements_addon_specific.txt | grep -v '^#' | grep -v '^\s*$' | grep '^six\|^future' | cut -d= -f1 | xargs poetry add --lock --dev 
            git rm requirements_addon_specific.txt || true
        fi
    fi
    sed 's|yarn.lock|*.lock|'  .reuse/dep5
    if [[ -f "package.json" ]]; then
        if [[ ! -f "yarn.lock" ]]; then
            npx yarn build || true
        fi
    fi

    if [[ -d .circleci ]]; then
        git rm -rf .circleci
    fi
    gh api /repos/$REPOORG/$REPO  -H 'Accept: application/vnd.github.nebula-preview+json' -X PATCH -F visibility=$REPOVISIBILITY
    git add . || exit 1
    git commit -am "test: wfe rollout changes" || exit 1
    git push -f --set-upstream origin test/common-template-wfe-rollout-changes|| exit 1
    gh pr create \
        --title "Bump repository configuration from template${PR_SUFFIX}" --fill  || exit 1    
fi
popd
