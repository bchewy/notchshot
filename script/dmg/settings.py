# SPDX-License-Identifier: MIT
# dmgbuild settings for NotchShot's drag-to-Applications disk image.
# script/package_release.py passes the paths below with -D; the layout matches
# make_background.swift (a 640 × 400-point window).

files = [defines["app"]]  # noqa: F821 (dmgbuild provides defines)
symlinks = {"Applications": "/Applications"}
icon = defines["volume_icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

format = "UDZO"
# Finder counts the title bar in the window height; the content stays 640 × 400.
window_rect = ((200, 160), (640, 428))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
show_icon_preview = False
include_list_view_settings = False
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    "NotchShot.app": (170, 180),
    "Applications": (470, 180),
}
