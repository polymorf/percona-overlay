# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/dev-db/mysql/mysql-5.5.14.ebuild,v 1.2 2011/07/14 03:58:44 jmbsvicetto Exp $

EAPI="4"

MY_PV="${PV/_r*}"
PERCONA_RELEASE="29.4"
PERCONA_PV="Percona-Server-$MY_PV-rel$PERCONA_RELEASE"
# keep this in sync with percona
PERCONA_MYSQL_VERSION_EXTRA="55"

inherit versionator
MIRROR_PV=$(get_version_component_range 1-2 ${PV})
SERVER_URI="http://www.percona.com/downloads/Percona-Server-$MIRROR_PV/Percona-Server-$MY_PV-$PERCONA_RELEASE/source/$PERCONA_PV.tar.gz"

S="${WORKDIR}/$PERCONA_PV"

# Build type
BUILD="cmake"
# gentoo sets BUILD_TYPE to "gentoo" by default
# this causes mysql cmake rules to not define DBUG_OFF resulting in a version
# string saying mysql got build with debug on (e.g. 5.5.1-debug) although
# mysql wasn't build with debug on. so just override this with a known type
CMAKE_BUILD_TYPE="RelWithDebInfo"

inherit toolchain-funcs mysql-v2
# only to make repoman happy. it is really set in the eclass
IUSE="$IUSE"

DESCRIPTION="A fast, multi-threaded, multi-user SQL database server."
HOMEPAGE="http://www.percona.com/"

# FIXME: move to mysql-v2.eclass
E_DEPEND="${E_DEPEND} dev-libs/libaio"
E_RDEPEND="${E_RDEPEND} dev-libs/libaio"

# remove MY_EXTRAS_VER
# FIXME: mysql-v2.eclass shouldn't add extra src uris if MY_EXTRAS_VER is empty
SRC_URI2=""
for x in ${SRC_URI}
do
	[[ $x =~ mysql-extras- ]] && continue
	SRC_URI2="${SRC_URI2} ${x}"
done
SRC_URI="${SRC_URI2}"

# cleanup IUSE. that's _really_ a hack
# FIXME: mysql-v2.eclass should check if MYSQL_COMMUNITY_FEATURES is already set
IUSE2=""
for x in ${E_IUSE}
do
	[[ $x =~ ^\+?community$ ]] && continue
	IUSE2="${IUSE2} ${x}"
done
E_IUSE="${IUSE2}"

# REMEMBER: also update eclass/mysql*.eclass before committing!
KEYWORDS="~alpha ~amd64 ~arm ~hppa ~ia64 ~ppc ~ppc64 ~s390 ~sh ~sparc ~x86 ~sparc-fbsd ~x86-fbsd"

DEPEND="|| ( >=sys-devel/gcc-3.4.6 >=sys-devel/gcc-apple-4.0 )"
RDEPEND="${RDEPEND}"

# Please do not add a naive src_unpack to this ebuild
# If you want to add a single patch, copy the ebuild to an overlay
# and create your own mysql-extras tarball, looking at 000_index.txt

src_prepare() {
	cd "${S}"
	# create an empty mysql-extras as we don't have any
	mkdir -p ${WORKDIR}/mysql-extras
	mysql-v2_src_prepare
	# set PERCONA_MYSQL_VERSION_EXTRA
	if [ -r "${S}/VERSION" ]
	then
		einfo "Setting MYSQL_VERSION_EXTRA to ${PERCONA_MYSQL_VERSION_EXTRA}"
		sed -i -e "\$a\MYSQL_VERSION_EXTRA=-${PERCONA_MYSQL_VERSION_EXTRA}" \
			-e 's/^MYSQL_VERSION_EXTRA=/#MYSQL_VERSION_EXTRA=/' "${S}/VERSION"
	fi
}

# a simple bash rename method used for some hacks/hooks
rename_function() {
	local orig=$(declare -f $1)
	local new="$2${orig#$1}"
	eval "$new"
}

# hook into mysql_lib_symlinks
# this creates some unnecessary and also wrong symlinks from mysql/plugins
# so try to remove them again (HACKISH)
# FIXME: i think that's a bug in mysql_lib_symlinks anyway
# e.g. mysql_lib_symlinks creates /usr/lib/qa_auth_client -> /usr/lib/mysql/plugin/qa_auth_client.so ?!
rename_function mysql_lib_symlinks mysql_lib_symlinks.orig
mysql_lib_symlinks() {
	mysql_lib_symlinks.orig $*

	local reldir
	reldir="${1}"
	pushd "${reldir}/usr/$(get_libdir)" &> /dev/null
	find . -maxdepth 1 -type l -printf "%f\0%l\n" | \
		awk -F'\0' '$2 ~ /mysql\/plugin/ { print $1 }' | \
		while read f; do
			rm -f "$f"
		done
	popd &> /dev/null
}

# hook into src_configure
# can be used to modify configure options
# e.g. disable some engines
#rename_function configure_cmake_standard configure_cmake_standard_orig
#configure_cmake_standard() {
#	configure_cmake_standard_orig
#}

#rename_function configure_cmake_minimal configure_cmake_minimal_orig
#configure_cmake_minimal_orig() {
#	configure_cmake_standard_orig
#}

# Official test instructions:
# USE='berkdb -cluster embedded extraengine perl ssl community' \
# FEATURES='test userpriv -usersandbox' \
# ebuild mysql-X.X.XX.ebuild \
# digest clean package
src_test() {

	local TESTDIR="${CMAKE_BUILD_DIR}/mysql-test"
	local retstatus_unit
	local retstatus_tests

	# Bug #213475 - MySQL _will_ object strenously if your machine is named
	# localhost. Also causes weird failures.
	[[ "${HOSTNAME}" == "localhost" ]] && die "Your machine must NOT be named localhost"

	if ! use "minimal" ; then

		if [[ $UID -eq 0 ]]; then
			die "Testing with FEATURES=-userpriv is no longer supported by upstream. Tests MUST be run as non-root."
		fi
		has usersandbox $FEATURES && eerror "Some tests may fail with FEATURES=usersandbox"

		einfo ">>> Test phase [test]: ${CATEGORY}/${PF}"
		addpredict /this-dir-does-not-exist/t9.MYI

		# Run CTest (test-units)
		cmake-utils_src_test
		retstatus_unit=$?
		[[ $retstatus_unit -eq 0 ]] || eerror "test-unit failed"

		# Ensure that parallel runs don't die
		export MTR_BUILD_THREAD="$((${RANDOM} % 100))"

		# create directories because mysqladmin might right out of order
		mkdir -p "${S}"/mysql-test/var-{tests}{,/log}

		# These are failing in MySQL 5.5 for now and are believed to be
		# false positives:
		#
		# main.information_schema, binlog.binlog_statement_insert_delayed,
		# main.mysqld--help-notwin
		# fails due to USE=-latin1 / utf8 default
		#
		# main.mysql_client_test:
		# segfaults at random under Portage only, suspect resource limits.
		#
		# sys_vars.plugin_dir_basic
		# fails because PLUGIN_DIR is set to MYSQL_LIBDIR64/plugin
		# instead of MYSQL_LIBDIR/plugin
		#
		# main.flush_read_lock_kill
		# fails because of unknown system variable 'DEBUG_SYNC'
		for t in main.mysql_client_test \
			binlog.binlog_statement_insert_delayed main.information_schema \
			main.mysqld--help-notwin main.flush_read_lock_kill \
			sys_vars.plugin_dir_basic ; do
				mysql-v2_disable_test  "$t" "False positives in Gentoo"
		done

		# Run mysql tests
		pushd "${TESTDIR}"

		# run mysql-test tests
		perl mysql-test-run.pl --force --vardir="${S}/mysql-test/var-tests"
		retstatus_tests=$?
		[[ $retstatus_tests -eq 0 ]] || eerror "tests failed"
		has usersandbox $FEATURES && eerror "Some tests may fail with FEATURES=usersandbox"

		popd

		# Cleanup is important for these testcases.
		pkill -9 -f "${S}/ndb" 2>/dev/null
		pkill -9 -f "${S}/sql" 2>/dev/null

		failures=""
		[[ $retstatus_unit -eq 0 ]] || failures="${failures} test-unit"
		[[ $retstatus_tests -eq 0 ]] || failures="${failures} tests"
		has usersandbox $FEATURES && eerror "Some tests may fail with FEATURES=usersandbox"

		[[ -z "$failures" ]] || die "Test failures: $failures"
		einfo "Tests successfully completed"

	else

		einfo "Skipping server tests due to minimal build."
	fi
}
