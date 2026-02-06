#!/bin/bash


# Define BRANCH
# BRANCH="release/19.3";
BRANCH=${1:-wp/6.7};
# Generate a file name by replacing the slash with a double dash.
BRANCH_FILE_NAME=$(echo $BRANCH | sed 's/\//-/g');

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Include the functions file.
source $CURRENT_DIR/functions.sh

# ## Check out the branch in the gutenberg directory.
cd $CURRENT_DIR/gutenberg-dev;
git fetch;
git checkout $BRANCH;
git pull;

# Get the commits from the merge base to HEAD.
git log $MERGE_BASE..HEAD --pretty=format:"%H" > $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt;
# Add new line to the end of the file.
echo "" >> $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt;

# Change to the gutenberg-build directory
cd $CURRENT_DIR/plugins/gutenberg-build;

# Unstage all the files in the directory
git reset --hard;


# Checkout trunk.
git checkout trunk;

# Checkout the main branch
git checkout main;

# If the branch exists, check it out.
if [[ $(git branch --list $BRANCH) ]]; then
	git checkout $BRANCH;

	# Get the latest commit message from the branch.
	commitSourceLine=$(git log -1 --pretty=%B | tail -r -n2 | tail -r -n1);

	# Get the last 42 characters of the commits source line.
	latestSourceCommit=$(echo $commitSourceLine | tail -c 41);

	echo "Most recent source commit: $latestSourceCommit";

	# Get the commits from the gutenberg directory after the latest commit.
	cd $CURRENT_DIR/gutenberg-dev;
	git log $latestSourceCommit..HEAD --pretty=format:"%H"  > $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt;
	# Add new line to the end of the file.
	echo "" >> $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt;

	isFirst=false;
else

	# The branch does not exist, so we need to find the fork point.
	cd $CURRENT_DIR/plugins/gutenberg-build;

	# Get the fork origin (trunk for release branches, release/* for wp branches)
	MERGE_BASE=$(fork_origin $BRANCH);

	# Ensure we are still in the build version
	cd $CURRENT_DIR/plugins/gutenberg-build;

	# Search the log for the commit containing a reference to the merge base.
	commitFromBuiltTrunk=$(git log --grep="Source: https://github.com/WordPress/gutenberg/commit/$MERGE_BASE" --pretty=%H --all);

	# If the commit source line is empty, then the branch is new.
	if [ -z "$commitFromBuiltTrunk" ]; then
		echo "No known fork point for $BRANCH";


		# Hard delete the branch
		git branch -D $BRANCH;

		# Create an orphan branch
		git checkout --orphan $BRANCH;

		# Reset the branch again
		git reset --hard;

		isFirst=true;
	else
		echo "Found common fork point for $BRANCH: $commitFromBuiltTrunk";

		# Create the branch from commitFromBuiltTrunk
		git checkout -b $BRANCH $commitFromBuiltTrunk;

		# Get the last 42 characters of the commits source line.
		latestSourceCommit=$(echo $commitSourceLine | tail -c 41);

		echo "Most recent source commit: $latestSourceCommit";

		# Get the commits from the gutenberg directory after merge.
		cd $CURRENT_DIR/gutenberg-dev;
		git log $MERGE_BASE..HEAD --pretty=format:"%H"  > $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt;
		# Add new line to the end of the file.
		echo "" >> $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt;

		isFirst=false;
	fi


fi


# exit;










# Put the commits in the reverse order
tail -r $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits.txt > $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits-reversed.txt;
echo "" >> $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits-reversed.txt;


## Loop through each commit from the bottom of the file and check it out.

# commit=c90d920de07c53dff82c5914635b56fafa503b7f;

while read commit; do
	# Change to the gutenberg directory
	cd $CURRENT_DIR/gutenberg-dev;
	git reset --hard;
	git clean -xdf .;
	commitCheckoutResponse=$(git checkout $commit);
	if [[ $? -ne 0 ]]; then
		echo "Failed to checkout commit $commit";
		# Go to the next commit.
		continue;
	fi

	# Ensure the checked out commit is actually the commit we want.
	logicCheckCommit=$(git log -1 --pretty=%H);
	if [ "$commit" != "$logicCheckCommit" ]; then
		echo "Failed to checkout commit $commit";
		# Go to the next commit.
		continue;
	fi

	# Get the short hash of the current commit.
	commitShortHash=$(git rev-parse --short HEAD);

	git reset --hard;
	git clean -xdf .;


	# Get the commit message
	commitMessage=$(git log -1 --pretty=%B);
	# Get the commit date.
	commitDate=$(git log -1 --pretty=%cd --date=format:'%Y-%m-%d %H:%M:%S');
	# Get the commit author.
	commitAuthor=$(git log -1 --pretty=%an);
	# Get the commit author email.
	commitAuthorEmail=$(git log -1 --pretty=%ae);

	# Get tags for the commit.
	commitTags=$(git --no-pager tag --points-at);

	echo "Commit: $commit";
	echo "is tagged with: ";
	echo $commitTags;


	# continue;

	# Get the build workflow for the commit.
	workflowID=$(gh run list --workflow build-plugin-zip.yml -c $commit --status completed --json databaseId --jq '.[].databaseId' | head -n1);

	# Return to the top direcoty
	cd $CURRENT_DIR;

	# Empty the gutenberg-zip directory
	rm -rf $CURRENT_DIR/gutenberg-zip/*;

	needToDoItTheHardWay=false;

	# Download the workflow artifacts if they exist. Fail gracefully if they don't.
	if [ -z "$workflowID" ]; then
		echo "No workflow found for commit $commit";
		needToDoItTheHardWay=true;
	else
		response=$(gh run download $workflowID --dir=$CURRENT_DIR/gutenberg-zip --repo=WordPress/gutenberg 2>&1);
		if [[ $? -eq 0 ]]; then
			echo "Downloaded workflow artifacts for commit $commit";
		else
			echo "Failed to download workflow artifacts for commit $commit";
			needToDoItTheHardWay=true;
		fi
	fi

	if [ "$needToDoItTheHardWay" = true ]; then
		cd $CURRENT_DIR/gutenberg-dev;
		# Run fnm use --install-if-missing
		fnm use --install-if-missing;
		npm i;

		# Run the script bin/build-plugin-zip.sh
		NO_CHECKS=true ./bin/build-plugin-zip.sh

		cd $CURRENT_DIR;
		mkdir -p $CURRENT_DIR/gutenberg-zip/gutenberg-plugin;
		mv $CURRENT_DIR/gutenberg-dev/gutenberg.zip $CURRENT_DIR/gutenberg-zip/gutenberg-plugin/gutenberg.zip;
	fi

	if [ "$isFirst" = true ]; then
		# Set the commit message to "First BUild"
		commitMessage="First Build";

		# git show $commit;
		isFirst=false;
	fi

	# Reset the gutenberg build directory.
	cd $CURRENT_DIR/plugins/gutenberg-build;
	git reset --hard;

	# Git remove all th	e files in the directory
	git rm -rfq .


	# Extract the gutenberg.zip file to the gutenberg-build directory
	unzip -o $CURRENT_DIR/gutenberg-zip/gutenberg-plugin/gutenberg.zip -d $CURRENT_DIR/plugins/gutenberg-build;

	# Replace the readme file with the custom version.
	rm $CURRENT_DIR/plugins/gutenberg-build/README.md;
	cp $CURRENT_DIR/_replacement-readme.md $CURRENT_DIR/plugins/gutenberg-build/README.md;

	## Search and replace the %%COMMIT%% with the commit hash in the readme file.
	sed -i '' "s/%%COMMIT%%/$commit/g" $CURRENT_DIR/plugins/gutenberg-build/README.md;
	# Search and replace the %%COMMIT_SHORT%% with the commit short hash in the readme file.
	sed -i '' "s/%%COMMIT_SHORT%%/$commitShortHash/g" $CURRENT_DIR/plugins/gutenberg-build/README.md;
	# Search and replace the %%BRANCH%% with the branch name in the readme file.
	sed -i '' "s|%%BRANCH%%|$BRANCH|g" $CURRENT_DIR/plugins/gutenberg-build/README.md;

	# Add all the files to the git repository
	git add .

	# Commit the changes with the commit message, the source hash using the same date as the oriiinal commit, the author, and the author email.
	GIT_COMMITTER_DATE="$commitDate" GIT_COMMITTER_NAME="$commitAuthor" GIT_COMMITTER_EMAIL="$commitAuthorEmail" git commit --no-gpg-sign --allow-empty -m "$commitMessage" --date="$commitDate" --author="$commitAuthor <$commitAuthorEmail>" -m "Source: https://github.com/WordPress/gutenberg/commit/$commit";

	# Tag the commit with the tags.
	for commitTag in $commitTags; do
		# If the tag begins with "v" and the branch begins with "wp/" then skip it.
		if [[ $commitTag == v* && $BRANCH == wp/* ]]; then
			echo "Skipping tag $commitTag for commit $commit";
			continue;
		fi

		# If the tag already exists then replace it.
		if [[ $(git tag --list $commitTag) ]]; then
			echo "Tag $commitTag already exists for commit $commit";
			# Delete the tag locally
			git tag -d $commitTag;
			# Delete the tag remotely
			git push origin :refs/tags/$commitTag;
			# continue;
		fi


		echo "Tagging commit $commit with tag $commitTag";

		git tag --no-sign -f $commitTag;
	done

done < $CURRENT_DIR/log-files/$BRANCH_FILE_NAME-workflow-commits-reversed.txt;

cd $CURRENT_DIR/plugins/gutenberg-build;
git push origin $BRANCH:$BRANCH --force;
git push origin -f --tags;
