/*
    SPDX-FileCopyrightText: 2019 Aditya Mehra <aix.m@outlook.com>
    SPDX-FileCopyrightText: 2015 Marco Martin <mart@kde.org>
    SPDX-License-Identifier: GPL-2.0-or-later

    Overridden by this flake (see modules/bigscreen.nix). Organises the
    Bigscreen launcher into Media / Games / Utilities / Other sections instead
    of the stock Applications / Games split, and hides a configurable set of
    apps (XTerm, UVC Viewer, printing tools, ...).

    To reorganise: edit sectionTokens / hiddenTokens below. Apps are matched
    case-insensitively by their storage id or display name.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Window

import org.kde.plasma.plasmoid
import org.kde.kquickcontrolsaddons
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels

import "delegates" as Delegates
import org.kde.bigscreen as Bigscreen
import org.kde.private.biglauncher 1.0
import org.kde.plasma.private.kicker 0.1 as Kicker

FocusScope {
    id: root

    property Item navigationUp

    property real startY

    // Whether the view has scrolled down at least one row
    readonly property bool scrolledDown: launcherHomeColumn.currentSection && launcherHomeColumn.currentSection !== favAppsView.currentViewDownwards

    // --- Launcher organisation (edit here) --------------------------------
    readonly property var sectionTokens: ({
        "media":     ["vacuumtube", "stremio", "spotify", "kodi", "jellyfin", "open-tv", "blanket"],
        "games":     ["steamlink", "steam link", "moonlight"],
        "utilities": ["zen_browser", "zen browser", "discover", "konsole", "trayscale", "kate", "dolphin", "notepad next"]
    })
    // Never shown anywhere in the launcher (case-insensitive substrings).
    readonly property var hiddenTokens: ["xterm", "uvc", "print", "kwrite"]

    function _ids(sourceModel, row, parent) {
        var idx = sourceModel.index(row, 0, parent);
        var sid = sourceModel.data(idx, ApplicationListModel.ApplicationStorageIdRole);
        var name = sourceModel.data(idx, ApplicationListModel.ApplicationNameRole);
        return [(sid || "").toLowerCase(), (name || "").toLowerCase()];
    }
    function _matches(ids, tokens) {
        for (var i = 0; i < tokens.length; ++i) {
            for (var j = 0; j < ids.length; ++j) {
                if (ids[j].indexOf(tokens[i]) !== -1) {
                    return true;
                }
            }
        }
        return false;
    }
    function isHidden(sourceModel, row, parent) {
        return _matches(_ids(sourceModel, row, parent), hiddenTokens);
    }
    function sectionOf(sourceModel, row, parent) {
        var ids = _ids(sourceModel, row, parent);
        if (_matches(ids, hiddenTokens)) {
            return "hidden";
        }
        var names = ["media", "games", "utilities"];
        for (var i = 0; i < names.length; ++i) {
            if (_matches(ids, sectionTokens[names[i]])) {
                return names[i];
            }
        }
        return "other";
    }

    function activateAppView() {
        if (favAppsView.visible) {
            favAppsView.forceActiveFocus();
        } else if (recentView.visible) {
            recentView.forceActiveFocus();
        } else {
            mediaView.forceActiveFocus();
        }
    }

    Component.onCompleted: activateAppView()

    ColumnLayout {
        id: launcherHomeColumn
        anchors {
            left: parent.left
            right: parent.right
        }
        property Item currentSection
        readonly property Item firstSection: favAppsView.currentViewDownwards

        y: root.startY
        function intendedY() {
            if (!currentSection) {
                return startY;
            } else if (firstSection == currentSection) {
                return startY;
            }
            return Math.round(-currentSection.y + startY - currentSection.height / 2);
        }

        onCurrentSectionChanged: {
            y = y; // Break binding before starting animation to prevent glitches
            yAnim.to = intendedY();
            yAnim.restart();
        }

        NumberAnimation on y {
            id: yAnim
            duration: Kirigami.Units.veryLongDuration
            easing.type: Easing.OutCubic
            onFinished: {
                launcherHomeColumn.y = Qt.binding(() => launcherHomeColumn.intendedY());
            }
        }

        spacing: Kirigami.Units.largeSpacing * 3

        DelegateListView {
            id: favAppsView
            property var currentViewUpwards: visible ? favAppsView : root.navigationUp
            property var currentViewDownwards: visible ? favAppsView : recentView.currentViewDownwards

            title: i18n("Favorites")
            model: Plasmoid.favsListModel
            visible: count > 0
            currentIndex: 0
            focus: visible
            onActiveFocusChanged: if (activeFocus)
                launcherHomeColumn.currentSection = favAppsView
            delegate: Delegates.FavDelegate {
                property var modelData: typeof model !== "undefined" ? model : null
            }

            navigationUp: root.navigationUp
            navigationDown: recentView.currentViewDownwards
        }

        DelegateListView {
            id: recentView
            property var currentViewUpwards: visible ? recentView : favAppsView.currentViewUpwards
            property var currentViewDownwards: visible ? recentView : mediaView.currentViewDownwards
            readonly property int favoriteIdRole: Qt.UserRole + 3

            function sourceIndex(row) {
                return recentView.model.mapToSource(recentView.model.index(row, 0));
            }

            function storageId(row) {
                return sourceIndex(row).data(favoriteIdRole);
            }

            title: i18n("Recent")
            model: KItemModels.KSortFilterProxyModel {
                sourceModel: Kicker.RecentUsageModel {
                    shownItems: Kicker.RecentUsageModel.OnlyApps
                }
                filterRowCallback: function(sourceRow, sourceParent) {
                    const sourceIndex = sourceModel.index(sourceRow, 0, sourceParent);
                    const storageId = sourceIndex.data(recentView.favoriteIdRole);
                    if (Plasmoid.applicationListModel.isApplicationBlocklisted(storageId)) {
                        return false;
                    }
                    return !root.isHidden(sourceModel, sourceRow, sourceParent);
                }
            }

            visible: count > 0
            currentIndex: 0
            focus: visible && (favAppsView.currentViewUpwards === root.navigationUp)
            onActiveFocusChanged: if (activeFocus)
                launcherHomeColumn.currentSection = recentView

            delegate: Delegates.AppDelegate {
                property real sectionOpacity: 1.0
                property var modelData: typeof model !== "undefined" ? model : null
                applicationStorageId: recentView.storageId(index)
                launchApplication: function() {
                    recentView.model.sourceModel.trigger(recentView.sourceIndex(index).row, "", null);
                }
                iconImage: model.decoration
                text: model.display
            }

            navigationUp: favAppsView.currentViewUpwards
            navigationDown: mediaView.currentViewDownwards
        }

        DelegateListView {
            id: mediaView
            property var currentViewUpwards: visible ? mediaView : recentView.currentViewUpwards
            property var currentViewDownwards: visible ? mediaView : gamesView.currentViewDownwards

            title: i18n("Media")
            visible: count > 0
            enabled: count > 0
            model: KItemModels.KSortFilterProxyModel {
                sourceModel: Plasmoid.applicationListModel
                filterRowCallback: function (source_row, source_parent) {
                    return root.sectionOf(sourceModel, source_row, source_parent) === "media";
                }
            }

            currentIndex: 0
            focus: visible && (recentView.currentViewUpwards === root.navigationUp)
            onActiveFocusChanged: if (activeFocus)
                launcherHomeColumn.currentSection = mediaView
            delegate: Delegates.AppDelegate {
                property var modelData: typeof model !== "undefined" ? model : null
            }

            navigationUp: recentView.currentViewUpwards
            navigationDown: gamesView.currentViewDownwards
        }

        DelegateListView {
            id: gamesView
            property var currentViewUpwards: visible ? gamesView : mediaView.currentViewUpwards
            property var currentViewDownwards: visible ? gamesView : utilitiesView.currentViewDownwards

            title: i18n("Games")
            visible: count > 0
            enabled: count > 0
            model: KItemModels.KSortFilterProxyModel {
                sourceModel: Plasmoid.applicationListModel
                filterRowCallback: function (source_row, source_parent) {
                    return root.sectionOf(sourceModel, source_row, source_parent) === "games";
                }
            }

            currentIndex: 0
            focus: visible && (mediaView.currentViewUpwards === root.navigationUp)
            onActiveFocusChanged: if (activeFocus)
                launcherHomeColumn.currentSection = gamesView
            delegate: Delegates.AppDelegate {
                property var modelData: typeof model !== "undefined" ? model : null
            }

            navigationUp: mediaView.currentViewUpwards
            navigationDown: utilitiesView.currentViewDownwards
        }

        DelegateListView {
            id: utilitiesView
            property var currentViewUpwards: visible ? utilitiesView : gamesView.currentViewUpwards
            property var currentViewDownwards: visible ? utilitiesView : otherView.currentViewDownwards

            title: i18n("Utilities")
            visible: count > 0
            enabled: count > 0
            model: KItemModels.KSortFilterProxyModel {
                sourceModel: Plasmoid.applicationListModel
                filterRowCallback: function (source_row, source_parent) {
                    return root.sectionOf(sourceModel, source_row, source_parent) === "utilities";
                }
            }

            currentIndex: 0
            focus: visible && (gamesView.currentViewUpwards === root.navigationUp)
            onActiveFocusChanged: if (activeFocus)
                launcherHomeColumn.currentSection = utilitiesView
            delegate: Delegates.AppDelegate {
                property var modelData: typeof model !== "undefined" ? model : null
            }

            navigationUp: gamesView.currentViewUpwards
            navigationDown: otherView.currentViewDownwards
        }

        DelegateListView {
            id: otherView
            property var currentViewUpwards: visible ? otherView : utilitiesView.currentViewUpwards
            property var currentViewDownwards: visible ? otherView : null

            title: i18n("Other")
            visible: count > 0
            enabled: count > 0
            model: KItemModels.KSortFilterProxyModel {
                sourceModel: Plasmoid.applicationListModel
                filterRowCallback: function (source_row, source_parent) {
                    return root.sectionOf(sourceModel, source_row, source_parent) === "other";
                }
            }

            currentIndex: 0
            focus: visible && (utilitiesView.currentViewUpwards === root.navigationUp)
            onActiveFocusChanged: if (activeFocus)
                launcherHomeColumn.currentSection = otherView
            delegate: Delegates.AppDelegate {
                property var modelData: typeof model !== "undefined" ? model : null
            }

            navigationUp: utilitiesView.currentViewUpwards
            navigationDown: null
        }
    }
}
