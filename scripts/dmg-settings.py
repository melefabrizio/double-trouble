# dmgbuild settings for the release disk image. Paths come in as -D defines
# from scripts/make-dmg.sh. Icon positions match Design/dmg-background.png.
app = defines["app"]
app_name = app.rstrip("/").split("/")[-1]

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

icon = defines["volume_icon"]
background = defines["background"]

format = "UDZO"
filesystem = "HFS+"

window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (170, 190),
    "Applications": (470, 190),
}
