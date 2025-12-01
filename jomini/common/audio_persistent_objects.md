# Audio Persistent Objects

Defines persistent audio objects

Example

```
music_manager = {
    name = "Music Manager"             # name of object in Wwise
    scope = asap                       # scope for the object (see below)
    init_event = start_debug_music     # Wwise event to call when the object is created
    deinit_event = stop_debug_music    # Wwise event to call when the object is destroyed
}
```

Scope can be one of:
* asap    - init as soon as possible on the game start and persist until the game closes
* menu    - init when the main menu is loaded and persist until the game closes
* ingame  - init when the game world (galaxy) is loaded and persist until the exit to the menu

`music_manager` is a required database entry. If missing, it will be created with default settings
