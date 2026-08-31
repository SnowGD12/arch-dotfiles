//@ pragma UseQApplication
import Quickshell

ShellRoot {
    Bar {
        onVolumeMixerToggleRequested: volumeMixer.toggle()
        onPowerMenuToggleRequested: {
            if (powerMenu.open)
                powerMenu.hide()
            else
                powerMenu.show()
        }
        onCalendarToggleRequested: calendarPopup.toggle()
    }

    // Native Quickshell notification daemon
    NotificationDaemon {
        id: notificationDaemon
        onHistoryNotification: entry => calendarPopup.addNotification(entry)
    }

    CalendarNotificationPopup {
        id: calendarPopup
    }

    ClipboardHistoryPopup {
        id: clipboardPopup
    }

    AppLauncher {
        id: appLauncher
    }

    VolumeMixer {
        id: volumeMixer
    }

    PowerMenu {
        id: powerMenu
    }

    EmojiPicker {
        id: emojiPicker
    }

    WallpaperPicker {
        id: wallpaperPicker
    }
}
