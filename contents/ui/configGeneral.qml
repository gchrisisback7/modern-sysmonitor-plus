import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_showNetwork: showNetwork.checked
    property alias cfg_showCpu: showCpu.checked
    property alias cfg_showRam: showRam.checked
    property alias cfg_showGpu: showGpu.checked
    property alias cfg_showVram: showVram.checked
    property alias cfg_showDisks: showDisks.checked
    property alias cfg_updateInterval: updateInterval.value
    property alias cfg_cpuFanNumber: cpuFanNumber.value

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showNetwork
            Kirigami.FormData.label: i18n("Show in the widget:")
            text: i18n("Network")
        }
        QQC2.CheckBox {
            id: showCpu
            text: i18n("CPU")
        }
        QQC2.CheckBox {
            id: showRam
            text: i18n("RAM")
        }
        QQC2.CheckBox {
            id: showGpu
            text: i18n("GPU")
        }
        QQC2.CheckBox {
            id: showVram
            text: i18n("VRAM")
        }
        QQC2.CheckBox {
            id: showDisks
            text: i18n("Disks (temperature and usage)")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            id: updateInterval
            Kirigami.FormData.label: i18n("Update every (seconds):")
            from: 1
            to: 60
        }

        QQC2.SpinBox {
            id: cpuFanNumber
            Kirigami.FormData.label: i18n("CPU fan number:")
            from: 0
            to: 16
            textFromValue: function(value) {
                return value === 0 ? i18n("Automatic") : i18n("Fan %1", value)
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Most motherboards do not name their fans, so the CPU fan cannot be recognised automatically. Pick its number here (the numbers match fan1, fan2, ... in the output of the \"sensors\" command) and its speed is shown in the CPU card.")
        }
    }
}
