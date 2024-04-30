set -e

if [ ! -d "$CI_ARCHIVE_PATH" ]; then
    echo "Archive does not exist, skipping Sentry upload"
    exit 0
fi

# This is necessary in order to have sentry-cli
# install locally into the current directory
export INSTALL_DIR=$PWD

if [[ $(command -v sentry-cli) == "" ]]; then
    echo "Installing Sentry CLI"
    curl -sL https://sentry.io/get-cli/ | bash
fi

echo "Authenticate to Sentry"
$CI_PRIMARY_REPOSITORY_PATH/ci_scripts/sentry-cli login --auth-token $SENTRY_AUTH_TOKEN

echo "Uploading dSYM to Sentry"
$CI_PRIMARY_REPOSITORY_PATH/ci_scripts/sentry-cli debug-files upload --include-sources -o 'philipp-bolte' -p 'oscar' $CI_ARCHIVE_PATH
