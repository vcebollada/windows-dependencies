#!/bin/bash

function show_help()
{
  echo " "
  echo " "
  echo "=============================="
  echo " update-vcpkg-ports-helper.sh "
  echo "=============================="
  echo " "
  echo "Finds the latest commits of the remote origin of 'windows-dependencies', 'dali-core',"
  echo "'dali-adaptor' and 'dali-toolkit'."
  echo " "
  echo "Downloads the source code to the 'vcpkg/downloads' folder and calculates the sha512 hash needed"
  echo "to be set up in the vcpkg port files."
  echo " "
  echo "Checks if DALi builds. If it does it creates a commit with the new DALi version tag in the vcpkg repository."
  echo " "
  echo "Pushes the commit to the user's github repository and if the 'hub' command is present in the path"
  echo "it creates a pull-request in the DALi's github repository."
  echo " "
  echo "Requirements: "
  echo " * the 'VCPKG_FOLDER' environment variable has to be set with the directory where the 'vcpkg'"
  echo "   git repository is located."
  echo " * the script must be called from where the DALi git repositories are located. "
  echo " "
  echo " * the 'vcpkg' directory must have the sha512sum.exe command somewhere in its subdirectories. Otherwise,"
  echo "   the SHA_COMMAND environment variable must be set with the command."
  echo " "
  echo " * A github account with a fork of https://github.com/dalihub/vcpkg if it's wanted to push"
  echo "   the commit with the new version of DALi automatically."
  echo " "
  echo " * the 'hub' command if it's wanted to create the pull-request automatically."
  echo "   https://github.com/github/hub/releases"
  echo " "
  echo "Options: "
  echo " -p | -httpProxy | --httpProxy     Sets the http proxy. By default the proxy is set to 106.1.18.35:8080"
  echo " -s | -httpsProxy | --httpsProxy   Sets the https proxy. By default the proxy is set to 106.1.18.35:8080"
  echo " -n | -noProxy | --noProxy         Doesn't set any proxy."
  echo " -h | -help | --help               Prints the help."
}

function printUpdateInfo
{
  VCPKG_FOLDER=$1
  daliRepositories=$2
  daliTags=$3
  daliVcpkgPorts=$4
  commitIds=$5
  sha512Hash=$6
  
  echo " "
  echo " "
  echo "In case the CONTROL and portfile.cmake files need to be updated manually here is the info. Check if it's right:"
  index=0
  for repo in ${daliRepositories[@]}
  do
    if [ "$index" != 0 ]; then # windows-dependencies has no tags.
      echo "* update the "$VCPKG_FOLDER/vcpkg/ports/${daliVcpkgPorts[$index]}/CONTROL" file and set the "${daliTags[$index]}" tag."
    fi
    echo "* update the "$VCPKG_FOLDER/vcpkg/ports/${daliVcpkgPorts[$index]}/portfile.cmake" file and set:"
    echo "  - the "${commitIds[$index]}" REF."
    echo "  - the "${sha512Hash[$index]}" SHA512."

    index=$((index+1))
  done
}

################################################################################
# Checks if the environment VCPKG_FOLDER variable has been set.
################################################################################
if [ -z ${VCPKG_FOLDER+x} ]; then
  echo "The variable VCPKG_FOLDER is unset";
  echo "Define an environment variable to set the path to the VCPKG folder"
  echo "$ export VCPKG_FOLDER=C:/Users/username/Workspace/VCPKG_TOOL"
  echo ""
  show_help
  exit
fi

if [ ! -d $VCPKG_FOLDER/vcpkg ]; then
  echo "The "$VCPKG_FOLDER" must contain the vcpkg git repository"
fi

################################################################################
# Checks if the script has been executed from a folder that contains
# 'windows-dependencies', 'dali-core', 'dali-adaptor' and 'dali-toolkit'.
################################################################################
if [ ! -d "windows-dependencies" ] || [ ! -d "dali-core" ] || [ ! -d "dali-adaptor" ] || [ ! -d "dali-toolkit" ]; then
  echo "The script must be executed from a directory that contains the 'windows-dependencies', 'dali-core', 'dali-adaptor' and 'dali-toolkit' directories."
  echo ""
  show_help
  exit
fi

################################################################################
# Find the sha512 command
################################################################################
if [ -z ${SHA_COMMAND+x} ]; then
  SHA_COMMAND=$(find $VCPKG_FOLDER | grep sha512sum.exe)
  if [ -z "$SHA_COMMAND" ]; then
    echo "Can't find the sha512sum.exe command. Aborting ..."
    echo "Set the SHA_COMMAND variable with an appropriate sha512sum command and try again."
    show_help
    exit
  fi
fi

################################################################################
# Parse the script options.
################################################################################
http_proxy_ip="106.1.18.35:8080"
https_proxy_ip=$http_proxy_ip

use_proxy=1;

while true; do
  case "$1" in
    -p | -httpProxy | --httpProxy) http_proxy_ip="$2"; https_proxy_ip=$http_proxy_ip; shift ;;
    -s | -httpsProxy | --httpsProxy) https_proxy_ip="$2"; shift ;;
    -n | -noProxy | --noProxy) use_proxy=false ;;
    -h | -help | --help)
      show_help
      exit
      ;;
    -- ) break ;; # End of options.
    * ) break ;;
  esac
  shift # Shifts the script options
done

################################################################################
# Set up proxy
################################################################################
if [ "$use_proxy" = 1 ]; then
  export VCPKG_PROXY="${http_proxy_ip}"
  export HTTP_PROXY="http://${http_proxy_ip}/"
  export HTTPS_PROXY="http://${https_proxy_ip}/"
fi

################################################################################
# Some global vars
################################################################################
daliRepositories=(windows-dependencies dali-core dali-adaptor dali-toolkit)
daliVcpkgPorts=(dali-windows-dependencies dali2-core dali2-adaptor dali2-toolkit)
commitIds=()
sha512Hash=()
daliTags=()

index=0
daliTag=""

################################################################################
# Download the latest version of DALi from github
################################################################################
for repo in ${daliRepositories[@]}
do
  # Find the latest commit ID
  cd $repo

  echo "Fetching patches from 'origin'"
  git fetch origin
  commitId=$(git log origin --format="%H" -n 1)
  commitIds[$index]=$commitId

  # Download the repositories from github to the VCPKG downloads folder.
  source=https://codeload.github.com/dalihub/$repo/tar.gz/$commitId
  target=$VCPKG_FOLDER/vcpkg/downloads/dalihub-$repo-$commitId.tar.gz

  echo "Downloading "$source " --> " $target
  curl $source --output $target

  # Get the sha512 hash from the downloaded target.
  hash=$(eval $SHA_COMMAND" "$target" | cut -c 1-128")
  sha512Hash[$index]=$hash
  echo "hash : ["$hash"]"

  # Get the repository tag
  if [ "$index" != 0 ]; then # windows-dependencies has no tags.
    daliTag=$(git describe origin | cut -d_ -f2 | cut -d- -f1)
    daliTags[$index]=$daliTag
    echo "DALi tag : ["$daliTag"]" 
  fi

  index=$((index+1))
  cd -
done

################################################################################
# Update the control files
################################################################################
index=0
for repo in ${daliVcpkgPorts[@]}
do
  if [ "$index" != 0 ]; then # windows-dependencies has no tags.
    validTag=true;
    # Check it's a valid tag
    major=$(echo ${daliTags[$index]} | cut -d. -f 1 -s)
    minor=$(echo ${daliTags[$index]} | cut -d. -f 2 -s)
    micro=$(echo ${daliTags[$index]} | cut -d. -f 3 -s)

    # Ensure all versions are present
    if [ "$major" = "" ] || [ "$minor" = "" ] || [ "$micro" = "" ]
    then
      validTag=false
    fi

    # Ensure all versions are actually numbers
    if [[ ! $major =~ ^-?[0-9]+$ ]] || [[ ! $minor =~ ^-?[0-9]+$ ]] || [[ ! $micro =~ ^-?[0-9]+$ ]]
    then
      validTag=false
    fi

    if $validTag; then
      echo "Updating CONTROL file with "$major"."$minor"."$micro
      $(sed -i -r "s/Version: [0-9]+[.][0-9]+[.][0-9]+/Version: "$major"."$minor"."$micro"/" $VCPKG_FOLDER/vcpkg/ports/$repo/CONTROL)
    else
      echo "Invalid tag for "$VCPKG_FOLDER/vcpkg/ports/$repo". The CONTROL file has to be updated manually."
    fi
  fi
  index=$((index+1))
done

################################################################################
# Update the portfile.cmake files
################################################################################
index=0
for repo in ${daliVcpkgPorts[@]}
do
  echo "Updating portfile.cmake file with :"
  echo ${commitIds[$index]}" commit id and"
  echo ${sha512Hash[$index]}" hash."
  $(sed -i -r "s/REF [0-9a-f]+/REF "${commitIds[$index]}"/" $VCPKG_FOLDER/vcpkg/ports/$repo/portfile.cmake)
  $(sed -i -r "s/SHA512 [0-9a-f]+/SHA512 "${sha512Hash[$index]}"/" $VCPKG_FOLDER/vcpkg/ports/$repo/portfile.cmake)
  index=$((index+1))
done

################################################################################
# Check the control and portfile.cmake files have been updated correctly.
################################################################################

index=0
updateSuccess=1
for repo in ${daliVcpkgPorts[@]}
do
  cd $VCPKG_FOLDER/vcpkg/ports/$repo

  # check whether the CONTROL file has the right tag
  if [ "$index" != 0 ]; then # windows-dependencies has no tags.
    push=$(cat CONTROL | egrep ${daliTags[$index]} | wc -l)
    if [ "$push" != 1 ]; then
      updateSuccess=0;
      break;
    fi
  fi

  # check whether the portfile.cmake has the right commit id.
  push=$(cat portfile.cmake | egrep ${commitIds[$index]} | wc -l)

  if [ "$push" != 1 ]; then
    updateSuccess=0;
    break;
  fi
  
  # check whether the portfile.cmake has the right sha 512 hash.
  push=$(cat portfile.cmake | egrep ${sha512Hash[$index]} | wc -l)
  
  if [ "$push" != 1 ]; then
    updateSuccess=0;
    break;
  fi

  cd -
  index=$((index+1))
done

if [ "$updateSuccess" = 0 ]; then
  echo "Failed to update the CONTROL and portfile.cmake files."
  # Prints the commit id and the sha512 hash
  printUpdateInfo $VCPKG_FOLDER $daliRepositories $daliTags $daliVcpkgPorts $commitIds $sha512Hash
  exit
fi

################################################################################
# Check the DALi ports build
################################################################################

echo "Check the DALi ports build."
cd $VCPKG_FOLDER/vcpkg
./vcpkg remove dali-windows-dependencies dali-core dali2-core dali-adaptor dali2-adaptor dali-toolkit dali2-toolkit # removes the old dali ports as well (without '2')
./vcpkg install dali2-toolkit

binFiles=(dali2-core.dll dali2-adaptor.dll dali2-toolkit.dll)
libFiles=(dali-windows-dependencies.lib dali2-core.lib dali2-adaptor.lib dali2-toolkit.lib)
buildSuccess=1
for file in ${binFiles[@]}
do
  if [ ! -f $VCPKG_FOLDER/vcpkg/installed/x86-windows/bin/$file ] || [ ! -f $VCPKG_FOLDER/vcpkg/installed/x86-windows/debug/bin/$file ]; then
    buildSuccess=0
    break
  fi
done

if [ "$buildSuccess" = 1 ]; then
  for file in ${libFiles[@]}
  do
    if [ ! -f $VCPKG_FOLDER/vcpkg/installed/x86-windows/lib/$file ] || [ ! -f $VCPKG_FOLDER/vcpkg/installed/x86-windows/debug/lib/$file ]; then
      buildSuccess=0
      break
    fi
  done
fi

if [ "$buildSuccess" = 1 ]; then
  echo "Build successful."
else
  echo "Build failed. Check the vcpkg logs."
  exit 1
fi
cd -

################################################################################
# Commit the changes in the vcpkg repository, push to github
# and create a pull request.
################################################################################

# commit the changes in the vcpkg repository.
echo "Add the changes to the vcpkg git repository and commit."
cd $VCPKG_FOLDER/vcpkg
index=0
for repo in ${daliRepositories[@]}
do
  if [ "$index" != 0 ]; then # windows-dependencies has no tags.
    $(git add $VCPKG_FOLDER/vcpkg/ports/${daliVcpkgPorts[$index]}/CONTROL)
  fi
  $(git add $VCPKG_FOLDER/vcpkg/ports/${daliVcpkgPorts[$index]}/portfile.cmake)
  index=$((index+1))
done
commitMessage="Update DALi to version "$daliTag

result=$(git commit -s -m "$commitMessage")
echo $result
  
echo "Push changes to github"

echo "type your github username : "
read gitHubUserName
if [[ "" = "$gitHubUserName" ]]
then
  echo "No github username provided."
  exit 1
fi

echo "type the repository name (default is vcpkg) : "
read gitHubRepoName
if [[ "" = "$gitHubRepoName" ]]
then
  gitHubRepoName="vcpkg"
fi

echo "    user name : ["$gitHubUserName"]"
echo "    repo name : ["$gitHubRepoName"]"

$(git push https://github.com/$gitHubUserName/$gitHubRepoName --force HEAD:master)

if command -v hub
then
  echo "Create a pull request."
  hub pull-request -f --no-edit
else
  echo "The hub command is not in the path."
  echo "The pull request to merge the patch with the new version of DALi from your"
  echo "github repository to DALi's github has to be created manually."
  echo "The hub command can be downloaded from https://github.com/github/hub/releases"
  echo "Follow their instructions to install it."
fi

cd -

