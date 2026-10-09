# Copyright 2021-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit autotools git-r3

DESCRIPTION="Mouse gestures for X"
HOMEPAGE="https://github.com/deters/mygestures/"
EGIT_REPO_URI="https://github.com/deters/mygestures"
EGIT_COMMIT="0c033bf" #pin before 2026 AI rewrite

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~x86"

RDEPEND="
	dev-libs/libxml2
	x11-libs/libX11
	x11-libs/libXi
	x11-libs/libXrender
	x11-libs/libXtst
"
DEPEND="
	${RDEPEND}
	x11-base/xorg-proto
"
BDEPEND="
	virtual/pkgconfig
"

PATCHES=(
	"${FILESDIR}"/${PN}-2.0-gcc14.patch
)

src_unpack() {
	git-r3_src_unpack
}

src_prepare() {
	default

	eautoreconf
}

src_install() {
	dobin src/mygestures #814482

	dodoc README.md

	insinto /etc
	doins mygestures.xml
}
