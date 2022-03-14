#!/usr/bin/env bash
# echo all the commands 
set -x
REPOORG=splunk
BRANCH_NAME=ci/common-template-rollout-github-actions

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
    poetry add --lock --dev splunk-add-on-ucc-framework lovely-pytest-docker reuse pytest splunk-packaging-toolkit pytest-xdist pytest-splunk-addon pytest-expect pytest-splunk-addon-ui-smartx pytest-rerunfailures coverage pytest-cov
    
    git init
    git config user.email ${GH_USER_EMAIL}
    git config user.name ${GH_USER_ADMIN}
    git submodule add git@github.com:$REPOORG/addonfactory-splunk_sa_cim.git deps/apps/Splunk_SA_CIM

    git add .
    git commit -am "base"
    git tag -a v0.2.0 -m "CI base"

    gh repo create $REPOORG/$REPO --$REPOVISIBILITY --confirm
    gh api orgs/$REPOORG/teams/products-shared-services-all/repos/$REPOORG/$REPO --raw-field 'permission=maintain' -X PUT
    gh api orgs/$REPOORG/teams/productsecurity/repos/$REPOORG/$REPO --raw-field 'permission=read' -X PUT
    gh api orgs/$REPOORG/teams/products-gdi-addons-adminrepo/repos/$REPOORG/$REPO --raw-field 'permission=admin' -X PUT
    gh api orgs/$REPOORG/$REPO -X PATCH --field default_branch=main
    gh api /repos/$REPOORG/$REPO  -H 'Accept: application/vnd.github.nebula-preview+json' -X PATCH -F visibility=$REPOVISIBILITY

    git remote add origin https://${GH_USER_ADMIN}:${GH_TOKEN_ADMIN}@github.com/$REPOORG/$REPO.git
    git checkout -b main
    git push --set-upstream origin main
    git tag -a v$(crudini --get package/default/app.conf launcher version) -m "Release"
    git push --follow-tags

else
    echo Repository is existing

    gh api repos/$REPOORG/$REPO --raw-field 'visibility=${REPOVISIBILITY}' -X PATCH || true
    
    echo "adding permission for teams"
    gh api orgs/$REPOORG/teams/products-gdi-addons-adminrepo/repos/$REPOORG/$REPO --raw-field 'permission=admin' -X PUT

    if [ ! -d "work/$REPO" ]; then
        #hub clone $REPOORG/$REPO work/$REPO
        git clone --depth 1 https://${GH_USER_ADMIN}:${GH_TOKEN_ADMIN}@github.com/$REPOORG/$REPO.git work/$REPO || exit 1
        pushd work/$REPO || exit 1
        git checkout main || exit 1
    else
        pushd work/$REPO || exit 1
        git fetch
        git checkout main || exit 1
        git pull || exit 1
    fi
    git remote set-url origin https://${GH_USER_ADMIN}:${GH_TOKEN_ADMIN}@github.com/$REPOORG/$REPO.git

    ( git checkout "$BRANCH_NAME"  && git checkout main && git branch -D "$BRANCH_NAME" ) || true
    git checkout -B "$BRANCH_NAME" main
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

    git rm splunk_add_on_ucc_framework-* || true        

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
    if [[ -d "tests/ui" ]]; then
        rsync -avh --include ".*" ../../conditional/ .
    fi

    files_to_delete=(
        "tests/data/wordlist.txt"
        "splver.py"
        "packagingScript.sh"
        "build.sh"
        "tests/knowledge/requirements.txt"
        "tests/knowledge/wordlist.txt"
        "tests/ui/requirements.txt"
        "tests/pytest.ini"
        "tests/test_addon.py"
        "tests/__init__.py"
        "tests/pytest-ci.ini"
        "tests/conftest.py"
        "tests/requirements.txt"
        "requirements.txt"
        ".python-version"
        ".github/workflows/cla.yaml"
        "tests/backend_entrypoint.sh"
        ".github/workflows/reuse.yml"
        ".github/workflows/snyk.yaml"
        ".github/workflows/rebase.yml"
        ".releaserc.yaml"
        "NOTICE"
        "package/lib/py2/requirements.txt"
        "requirements_py2_dev.txt"
        "LICENSES/LicenseRef-Splunk-1-2020.txt"
        "semtag"
        "unit_test_requirements.txt"
        ".github/workflows/release-notes.yml"
        ".github/workflows/requirements_unit_test.yml"
    )

    for i in ${!files_to_delete[@]}; do
        if [[ -f "${files_to_delete[$i]}" ]]; then
            git rm "${files_to_delete[$i]}" || true
        fi
    done

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

    if [[ ! -f ".app-vetting.yaml" ]]; then
        touch .app-vetting.yaml
    fi
    
    if [ -f "tests/requirement_test/pytest-ci.ini" ]; then
        echo "tests/requirement_test/pytest-ci.ini found"
        sed -i "s/\/home\/circleci\/work\///g" tests/requirement_test/pytest-ci.ini
        sed -i "s/-n[[:space:]]*5/-n 1/g" tests/requirement_test/pytest-ci.ini
        sed -i '/^[[:space:]]*--splunk-data-generator=tests\/knowledge\/*[[:space:]]*$/d' tests/requirement_test/pytest-ci.ini
    fi
    
    if [ ! -d "tests/knowledge/samples" ]; then
        echo "No samples directory, changing pytest-xdist n parameter to 1"
        sed -i "s/-n[[:space:]]*5/-n 1/g" tests/knowledge/pytest-ci.ini
    else
        sed -i "s/-n[[:space:]]*1/-n 5/g" tests/knowledge/pytest-ci.ini
    fi

    sed -i 's/LicenseRef-Splunk-1-2020/LicenseRef-Splunk-8-2021/g' .reuse/dep5
    python3 ../../tools/update_app_manifest_license.py

    gh api /repos/$REPOORG/$REPO  -H 'Accept: application/vnd.github.nebula-preview+json' -X PATCH -F visibility=$REPOVISIBILITY
    git add . || exit 1
    git commit -am "ci: common template rollout changes" || exit 1
    git push -f --set-upstream origin "$BRANCH_NAME" || exit 1
    sleep 10s
    gh pr create \
        --title "ci: Bump repository configuration from template${PR_SUFFIX}" --fill --head "$BRANCH_NAME" || exit 1
fi
popd
