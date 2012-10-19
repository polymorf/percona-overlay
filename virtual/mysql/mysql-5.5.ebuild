# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/virtual/mysql/mysql-5.5.ebuild,v 1.5
# 2012/04/18 06:12:08 robbat2 Exp $

EAPI="2"

DESCRIPTION="Virtual for MySQL client or database"
HOMEPAGE=""
SRC_URI=""

LICENSE=""
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~hppa ~ia64 ~ppc ~ppc64 ~s390 ~sh ~sparc ~x86
~sparc-fbsd ~x86-fbsd"
IUSE="embedded minimal static"

DEPEND=""
# TODO: add Drizzle and MariaDB here
RDEPEND="|| (
	=dev-db/mysql-${PV}*[embedded=,minimal=,static=]
	=dev-db/mariadb-${PV}*[embedded=,minimal=,static=]
	=dev-db/percona-server-${PV}*[embedded=,minimal=,static=]
)"
