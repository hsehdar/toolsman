#!/bin/bash

function __display_app_name_banner() {
	local STRING_TO_ECHO=$(printf "%-$(expr length "${@}")s");
	echo -e "  ${STRING_TO_ECHO// /_}__\n / ${STRING_TO_ECHO// / } \\\\\n | ${@} |\n \\\\${STRING_TO_ECHO// /_}__/";
}

function __display_last_message() {
	local CHARACTERS_COUNT=$(printf "%-$(expr length "${@}")s");
	echo -e "${@}\n${CHARACTERS_COUNT// /*}";
}

function __get_environment_info() {
	ARCH=$(uname -m)
	case $ARCH in
		armv5*) ARCH="armv5";;
		armv6*) ARCH="armv6";;
		armv7*) ARCH="arm";;
		aarch64) ARCH="arm64";;
		x86) ARCH="386";;
		x86_64) ARCH="amd64";;
		i686) ARCH="386";;
		i386) ARCH="386";;
	esac;
	OS=$(echo `uname` | tr '[:upper:]' '[:lower:]');
}

function __execute_command() {
	#https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables
	which $(echo "${@}" | cut -d " " -f1) &> /dev/null;
	if [[ "$?" -ne 0 ]];
	then	
		return 1;
	else
		unset T_STD T_ERR T_RET;
		local T_STD T_ERR T_RET;
		eval "$( eval "${@}" 2> >(T_ERR=$(cat); typeset -p T_ERR) > >(T_STD=$(cat); typeset -p T_STD); T_RET=$?; typeset -p T_RET )";
		printf "${T_STD}";
		return $T_RET;
	fi;
}

function __download_file() {
	local DESTINATION_FILE=${1};
	local DOWNLOAD_FILE_URL=${2};
	__execute_command "curl -sfIo /dev/null ${DOWNLOAD_FILE_URL}";
	if [[ "$?" -ne 0 ]];
	then
		return 1;
	fi;
	printf "⏬ Starting to download.\n";
	__execute_command "curl -sLo ${DESTINATION_FILE} ${DOWNLOAD_FILE_URL}";
	if [[ -f "${DESTINATION_FILE}" ]];
	then
		true;
	else
		false;
	fi;
}

function __verify_downloaded_file() {
	local FILE_TO_VERIFY=${1};
	local COMMAND_TO_VERIFY=${2};
	if [ ! -z "${COMMAND_TO_VERIFY}" ];
	then
		eval ${COMMAND_TO_VERIFY};
		if [[ "$?" -eq 0 ]];
		then
			printf "✅ Downloaded file verified successfully.\n";
			return 0;
		else
			rm -f "${FILE_TO_VERIFY}";
			return 1;
		fi;
	fi;
}

function __unzip_and_strip() {
	local ARCHIVE=${1};
	local DESTINATION_DIR=${2:-};
	local TEMP_DIR=$(mktemp -dt toolsman_zip_XXXXXX);
	unzip -qq ${ARCHIVE} -d ${TEMP_DIR};
	local SOURCE_DIR=$(dirname $(find ${TEMP_DIR} -type f -print -quit));
	cp -rpf ${SOURCE_DIR}/* ${DESTINATION_DIR}/.;
}

function __extract_deb_file() {
	local ARCHIVE=${1};
	local DESTINATION_DIR=${2:-};
	local TEMP_DIR=$(mktemp -dt toolsman_deb_XXXXXX);
	ar x ${ARCHIVE} data.tar.xz --output="${TEMP_DIR}";
	tar -xf ${TEMP_DIR}/data.tar.xz -C "${TEMP_DIR}";
	rm -f ${TEMP_DIR}/data.tar.xz;
	local SOURCE_DIR=$(find ${TEMP_DIR} -type d -name $(basename "${DESTINATION_DIR}") | grep "${DESTINATION_DIR}");
	cp -rpf "${SOURCE_DIR}"/* "${DESTINATION_DIR}"/.;
}

function __do_upgrade() {
	local DOWNLOAD_DIR=$(dirname ${1});
	local DOWNLOAD_FILE=$(basename ${1});
	local DOWNLOAD_FILE_EXT="${DOWNLOAD_FILE##*.}";
	local DESTINATION_DIR=${2};
	printf "⬆️ Starting to upgrade.\n";
	if [[ ! -f "${DOWNLOAD_DIR}/${DOWNLOAD_FILE}" ]];
	then
		false;
	else
		case "$DOWNLOAD_FILE_EXT" in
		gz | tgz | xz )
			tar xf "${DOWNLOAD_DIR}/${DOWNLOAD_FILE}" --directory "${DESTINATION_DIR}"/ --strip-components=$(tar tf "${DOWNLOAD_DIR}/${DOWNLOAD_FILE}" | grep "\/$" | sort | head -n1 | grep -o "\/" | wc -l);
			;;
		zip)
			__unzip_and_strip "${DOWNLOAD_DIR}/${DOWNLOAD_FILE}" "${DESTINATION_DIR}"/;
			;;
		deb)
			__extract_deb_file "${DOWNLOAD_DIR}/${DOWNLOAD_FILE}" "${DESTINATION_DIR}";
			;;
		*)
			rm -f ${DESTINATION_DIR}/${DOWNLOAD_FILE};
			mv ${DOWNLOAD_DIR}/${DOWNLOAD_FILE} ${DESTINATION_DIR}/${DOWNLOAD_FILE};
			chmod u+x ${DESTINATION_DIR}/${DOWNLOAD_FILE};
			;;
		esac;
		true;
	fi;
}

function __split_repo_line() {
	IFS=';' read -r -a REPO_LINE_ARRAY <<< "${@}";
}

function __read_repo_file() {
	readarray -t REPO_LINES < "${@}";
}

function main() {
	local REPO_LINE;
	for REPO_LINE in "${REPO_LINES[@]}";
	do
		if [ -z "${REPO_LINE}" ];
		then
			continue;
		fi;
		
		__split_repo_line "${REPO_LINE}";
		
		local APP_NAME=${REPO_LINE_ARRAY[0]};
		local INSTALLED_VERSION_COMMAND=${REPO_LINE_ARRAY[1]};
		local DESTINATION_DIRECTORY=${REPO_LINE_ARRAY[2]};
		local AVAILABLE_VERSION_COMMAND=${REPO_LINE_ARRAY[3]};
		local DOWNLOAD_FILE_URL=${REPO_LINE_ARRAY[4]};
		local VERIFY_DOWNLOADED_FILE_COMMAND=${REPO_LINE_ARRAY[5]};
		
		__display_app_name_banner "${APP_NAME#"#"}";

		if [[ ${REPO_LINE:0:1} = \# ]];
		then
			__display_last_message "⚠️  \"${APP_NAME#"#"}\" is not to be updated as it is commented.";
			continue;
		fi;
		
		if [ ! -d "${DESTINATION_DIRECTORY}" ] || [ ! "$(ls -A "${DESTINATION_DIRECTORY}")" ];
		then
			__display_last_message "⛔ Directory \"${DESTINATION_DIRECTORY}\" does not exists or it is empty. ";
			continue;
		fi;

		local INSTALLED_VERSION=$(__execute_command "${INSTALLED_VERSION_COMMAND}");
		if [[ "$?" -ne 0 || "$(echo ${INSTALLED_VERSION} | grep [0-9] -q && echo $?)" != "0" ]];
		then
			__display_last_message "⛔ Error getting installed version of ${APP_NAME}. ";
			continue;
		fi;
		local INSTALLED_VERSION_BY_BITS=( ${INSTALLED_VERSION//./ } );
		local INSTALLED_VERSION_MAJOR_BIT=${INSTALLED_VERSION_BY_BITS[0]};
		local INSTALLED_VERSION_MINOR_BIT=${INSTALLED_VERSION_BY_BITS[1]};
		local INSTALLED_VERSION_PATCH_BIT=${INSTALLED_VERSION_BY_BITS[2]};

		if [ -z "${DOWNLOAD_FILE_URL}" ];
		then
			printf "📌 Installed version: ${INSTALLED_VERSION}\n⏬ Checking for new version and self updating.\n";		
			SELF_UPDATE_OUTPUT=$(__execute_command "${AVAILABLE_VERSION_COMMAND}");
			__display_last_message "✅ Self updated and the ouput is \"${SELF_UPDATE_OUTPUT}\". ";
			continue;
		fi;
	
		local AVAILABLE_VERSION=$(__execute_command "$(echo ${AVAILABLE_VERSION_COMMAND} | sed "s|\${MajorVersionBit}|${INSTALLED_VERSION_MAJOR_BIT}|Ig")");
		if [[ "$?" -ne 0 ]];
		then
			__display_last_message "⛔ Error getting available version of ${APP_NAME} and ${INSTALLED_VERSION} version is installed. ";
			continue;
		fi;		

		DOWNLOAD_FILE=$(basename ${DOWNLOAD_FILE_URL} | sed "s|[-_.]x86[-_.]64||Ig;s|[-_.]\${OperatingSystem}64||Ig;s|[-_.]\${OperatingSystem}||Ig;s|[-_.]\${ProcessorArchitecture}||Ig;s|[-_.]\${AvailableVersion}||Ig;s|[-_.]v\${AvailableVersion}||Ig;s|\${AvailableVersion}||Ig");
		#Hack for Chrome/Edge where available version is followed by a dash and number. This version number is necessary in the download file URL only.
		DOWNLOAD_FILE_URL=$(echo "${DOWNLOAD_FILE_URL}" | sed "s|\${MajorVersionBit}|${INSTALLED_VERSION_MAJOR_BIT}|Ig;s|\${AvailableVersion}|${AVAILABLE_VERSION}|Ig;s|\${OperatingSystem}|${OS}|Ig;s|\${ProcessorArchitecture}|${ARCH}|Ig");
		VERIFY_DOWNLOADED_FILE_COMMAND=$(echo "${VERIFY_DOWNLOADED_FILE_COMMAND}" | sed "s|\${MajorVersionBit}|${INSTALLED_VERSION_MAJOR_BIT}|Ig;s|\${DestinationDir}|${DESTINATION_DIRECTORY}|Ig;s|\${AvailableVersion}|${AVAILABLE_VERSION}|Ig;s|\${OperatingSystem}|${OS}|Ig;s|\${ProcessorArchitecture}|${ARCH}|Ig");

		#Removing dash and number from available version as it is no more necessary.
		local AVAILABLE_VERSION=$(echo ${AVAILABLE_VERSION/-*/});

		if [[ "${INSTALLED_VERSION}" == "${AVAILABLE_VERSION}" ]];
		then
			printf "✅ No updates available.\n"
			__display_last_message "🏁 System up-to-date at ${INSTALLED_VERSION} version. ";
			continue;
		fi;

		if [[ "${INSTALLED_VERSION}" != "${AVAILABLE_VERSION}" ]];
		then
			printf "📌 Installed version: ${INSTALLED_VERSION}\n☁️  Available version: ${AVAILABLE_VERSION}\n";

			local TEMP_DOWNLOAD_FILE="$(mktemp -dt toolsman_download_XXXXXX)/${DOWNLOAD_FILE}";
			
			__download_file "${TEMP_DOWNLOAD_FILE}" "${DOWNLOAD_FILE_URL}";
			if [[ "$?" -ne 0 ]];
			then
				__display_last_message "⛔ Couldn't download ${APP_NAME} update of ${AVAILABLE_VERSION} version. ";
				continue;
			fi;

			__verify_downloaded_file "${TEMP_DOWNLOAD_FILE}" "$(echo ${VERIFY_DOWNLOADED_FILE_COMMAND} | sed "s|\${DestinationFile}|${TEMP_DOWNLOAD_FILE}|Ig")";
			if [[ "$?" -ne 0 ]];
			then
				__display_last_message "⚠️  Downloaded file verification failed.";
				continue;
			fi;

			__do_upgrade "${TEMP_DOWNLOAD_FILE}" "${DESTINATION_DIRECTORY}";
			if [[ "$(__execute_command ${INSTALLED_VERSION_COMMAND})" != "${AVAILABLE_VERSION}" ]];
			then
				__display_last_message "⚠️  Update done. However, there is mismatch in versions.";
				continue;
			fi;

			__display_last_message "💯 Updated. ";
		fi;
	done;
}

__get_environment_info;
__read_repo_file "$(dirname "$(readlink -f "$0")")/repo";
main;
exit;
