#!/bin/bash

function __display_app_name_banner() {
	local StringToEcho=$(printf "%-$(expr length "${@}")s");
	echo -e "  ${StringToEcho// /_}__\n / ${StringToEcho// / } \\\\\n | ${@} |\n \\\\${StringToEcho// /_}__/";
}

function __display_last_message() {
	local CharactersCount=$(printf "%-$(expr length "${@}")s");
	echo -e "${@}\n${CharactersCount// /*}"
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
	OS=$(echo `uname`|tr '[:upper:]' '[:lower:]');
}

function __unzip_and_strip() {
	local archive=${1};
	local destdir=${2:-};
	local tmpdir=$(mktemp -d);
	unzip -qq ${archive} -d ${tmpdir};
	local sourceDir=$(dirname $(find ${tmpdir} -type f -print -quit));
	cp -rpf ${sourceDir}/* ${destdir}/.;
	rm -rf ${tmpdir};
}

function __extract_deb_file() {
	local archive=${1};
	local destdir=${2:-};
	local tmpdir=$(mktemp -d);
	ar x ${archive} data.tar.xz --output="${tmpdir}";
	tar -xf ${tmpdir}/data.tar.xz -C "${tmpdir}";
	rm -f ${tmpdir}/data.tar.xz;
	local sourceDir=$(find ${tmpdir} -type d -name $(basename "${destdir}") | grep "${destdir}");
	cp -rpf "${sourceDir}"/* "${destdir}"/.;
	rm -rf "${tmpdir}" "${archive}";
}

function __extract_update_file() {
	local DestinationDir=${1};
	local DestinationFile=${2};
	local NameOfDestinationFile="${2%.*}";
	local ExtOfDestinationFile="${2##*.}";
	case "$ExtOfDestinationFile" in
	gz | tgz | xz )
		tar xf "${DestinationDir}/${DestinationFile}" --directory "${DestinationDir}"/ --strip-components=$(tar tf "${DestinationDir}/${DestinationFile}" | grep "\/$" | sort | head -n1 | grep -o "\/" | wc -l) && rm -f "${DestinationDir}/${DestinationFile}";
		;;
	zip)
		__unzip_and_strip "${DestinationDir}/${DestinationFile}" "${DestinationDir}"/ && rm -f "${DestinationDir}/${DestinationFile}";
		;;
	deb)
		__extract_deb_file "${DestinationDir}/${DestinationFile}" "${DestinationDir}";
		;;
	*)
		ExistingDestinationFile=$(echo ${DestinationFile} | sed $"s/[[:print:]]${OS}//g;s/[[:print:]]${ARCH}//g;s/[[:print:]]${AvailableVersion}//g");
		if [[ "${DestinationFile}" =~ "${ARCH}"  || "${DestinationFile}" =~ "${AvailableVersion}" || "${DestinationFile}" =~ "${OS}" ]];
		then
			rm -f ${DestinationDir}/${ExistingDestinationFile};
			mv ${DestinationDir}/${DestinationFile} ${DestinationDir}/${ExistingDestinationFile};
			chmod u+x ${DestinationDir}/${ExistingDestinationFile};
		else
			chmod u+x ${DestinationDir}/${DestinationFile};
		fi
		;;
	esac
}

function __execute_command() {
	#https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables
	unset t_std t_err t_ret;
	local t_std t_err t_ret;
	eval "$( eval "${@}" 2> >(t_err=$(cat); typeset -p t_err) > >(t_std=$(cat); typeset -p t_std); t_ret=$?; typeset -p t_ret )";
	printf "${t_std}";
	return $t_ret;
}

function __split_repo_line() {
	IFS=';' read -r -a strarr <<<"${@}";
}

function main() {
	readarray -t lines < "${@}";
	local line;
	for line in "${lines[@]}";
	do
		__split_repo_line "${line}";

		__display_app_name_banner "${strarr[0]}";

		if [ ! -d "${strarr[2]}" ] || [ ! "$(ls -A "${strarr[2]}")" ];
		then
			__display_last_message "⛔ Directory \"${strarr[2]}\" does not exists or it is empty. ";
			continue;
		fi;

		InstalledVersion=$(__execute_command "${strarr[1]}");
		if [[ "$?" -ne 0 ]];
		then
			__display_last_message "⛔ Error getting installed version of ${strarr[0]}. ";
			continue;
		fi;

		AvailableVersion=$(__execute_command "${strarr[3]}");
		if [[ "$?" -ne 0 ]];
		then
			__display_last_message "⛔ Error getting available version of ${strarr[0]} and it's ${InstalledVersion} version is installed. ";
			continue;
		fi;

		SourceFileUrl=$(__execute_command "echo ${strarr[4]} | sed \"s|\${AvailableVersion}|\${AvailableVersion}|Ig;s|\${OS}|\${OS}|Ig;s|\${ARCH}|\${ARCH}|Ig\"");
		#hack for Chrome where available version is followed by a dash and number. This version number is necessary in the source URL only and not else where.
		AvailableVersion=$(echo ${AvailableVersion/-*/});
		DestinationFile=$(__execute_command "basename ${strarr[4]} | sed \"s|\${AvailableVersion}|\${AvailableVersion}|Ig;s|\${OS}|\${OS}|Ig;s|\${ARCH}|\${ARCH}|Ig\"");

		if [[ "${InstalledVersion}" == "${AvailableVersion}" ]];
		then
			__display_last_message "✅ No updates available. 🏁 Version ${InstalledVersion} is already up-to-date.  ";
		else
			printf "📌 Installed version: ${InstalledVersion}\n☁️  Available version: ${AvailableVersion}\n⏬ Starting to download the new version now and then update it.\n";

			__execute_command "curl -sLo ${strarr[2]}/${DestinationFile} ${SourceFileUrl}";
			if [[ "$?" -ne 0 ]];
			then
				__display_last_message "⛔ Couldn't download ${strarr[0]} update of ${AvailableVersion} version. ";
				continue;
			fi;

			__extract_update_file "${strarr[2]}" "${DestinationFile}";

			if [[ "$(__execute_command ${strarr[1]})" != "${AvailableVersion}" ]];
			then
				__display_last_message "⛔ Update done. However, there is mismatch in versions. ";
				continue;
			fi;
			__display_last_message "💯 Updated. ";
		fi;
		continue;
	done;
}

__get_environment_info;
main "$(dirname "$(readlink -f "$0")")/repo"; exit;
