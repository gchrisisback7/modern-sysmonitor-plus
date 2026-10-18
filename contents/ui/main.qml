import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Default widget dimensions
    width: 320
    height: 670

    // Set background hints to configurable (allows custom transparency/blur container support)
    Plasmoid.backgroundHints: PlasmaCore.Types.ConfigurableBackground

    // Data properties
    property real cpuUsage: 0.0
    property real cpuTemp: 0.0
    property real ramUsed: 0.0
    property real ramTotal: 16.0
    property real ramPct: 0.0
    property real gpuUsage: 0.0
    property real gpuTemp: 0.0
    property real vramUsed: 0.0
    property real vramTotal: 8.0
    property real vramPct: 0.0

    // Extra GPU details (-1 = not available on this GPU), shown when "More" is pressed
    property bool gpuExpanded: false
    property real gpuTempJunction: -1
    property real gpuTempMem: -1
    property real gpuClock: -1
    property real gpuMemClock: -1
    property real gpuFanRpm: -1
    property real gpuFanPct: -1
    property real gpuPower: -1
    property real gpuPowerCap: -1

    // CPU fan (-1 = not found)
    property real cpuFanRpm: -1

    // Physical disks, filled from the stats script
    ListModel { id: diskModel }

    property string netDownSpeed: "0 B/s"
    property string netUpSpeed: "0 B/s"

    // Network speed history buffers for wave charts (30 data points)
    property var netDownHistory: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
    property var netUpHistory: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

    // DataSource execution wrapper using compatibility layer for shell runner
    Plasma5Support.DataSource {
        id: dbusSource
        engine: "executable"
        connectedSources: []
        
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName); // Unbind source to allow consecutive runs
            var stdout = data["stdout"];
            if (stdout) {
                try {
                    var stats = JSON.parse(stdout.trim());
                    root.updateStats(stats);
                } catch (e) {
                    console.log("JSON parsing error: " + e);
                }
            }
        }
        
        function fetch() {
            var scriptPath = Qt.resolvedUrl("data.py").toString();
            if (scriptPath.indexOf("file://") === 0) {
                scriptPath = scriptPath.substring(7);
            }
            // Run through python3 so the script does not need the executable bit
            connectSource("python3 \"" + scriptPath + "\" --cpu-fan " + Plasmoid.configuration.cpuFanNumber);
        }
    }

    // Interval timer for low-overhead update polling (2.0s interval)
    Timer {
        id: updateTimer
        interval: Math.max(1, Plasmoid.configuration.updateInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            dbusSource.fetch();
        }
    }

    // Returns v, or the default d when the value is missing / null
    function num(v, d) {
        return (v === undefined || v === null) ? d : v;
    }

    function fmtValue(v, digits, suffix) {
        return v < 0 ? "N/A" : v.toFixed(digits) + suffix;
    }

    function fanText() {
        if (root.gpuFanRpm >= 0) {
            return Math.round(root.gpuFanRpm) + " RPM" + (root.gpuFanPct >= 0 ? " · " + Math.round(root.gpuFanPct) + "%" : "");
        }
        return root.gpuFanPct >= 0 ? Math.round(root.gpuFanPct) + "%" : "N/A";
    }

    function powerText() {
        if (root.gpuPower < 0) return "N/A";
        if (root.gpuPowerCap > 0) return Math.round(root.gpuPower) + " / " + Math.round(root.gpuPowerCap) + " W";
        return Math.round(root.gpuPower) + " W";
    }

    // Disk sizes arrive in GB (1024-based, like the RAM card)
    function fmtSize(gb) {
        return gb >= 1000 ? (gb / 1024.0).toFixed(2) + " TB" : gb.toFixed(0) + " GB";
    }

    // Keep a ListModel in sync with a list of items {key, ...}.
    // The model is rebuilt only when the set of keys changes; otherwise values are
    // updated in place so the delegates do not flicker on every refresh.
    function syncModel(model, items) {
        var same = model.count === items.length;
        for (var i = 0; same && i < items.length; i++) {
            if (model.get(i).key !== items[i].key) same = false;
        }
        if (!same) {
            model.clear();
            for (var j = 0; j < items.length; j++) model.append(items[j]);
            return;
        }
        for (var a = 0; a < items.length; a++) {
            for (var prop in items[a]) {
                if (model.get(a)[prop] !== items[a][prop]) model.setProperty(a, prop, items[a][prop]);
            }
        }
    }

    function updateStats(stats) {
        root.cpuUsage = stats.cpu_usage !== undefined ? stats.cpu_usage : 0.0;
        root.cpuTemp = stats.cpu_temp !== undefined ? stats.cpu_temp : 0.0;
        root.ramUsed = stats.ram_used_gb !== undefined ? stats.ram_used_gb : 0.0;
        root.ramTotal = stats.ram_total_gb !== undefined ? stats.ram_total_gb : 16.0;
        root.ramPct = stats.ram_pct !== undefined ? stats.ram_pct : 0.0;
        root.gpuUsage = stats.gpu_usage !== undefined ? stats.gpu_usage : 0.0;
        root.gpuTemp = stats.gpu_temp !== undefined ? stats.gpu_temp : 0.0;
        root.vramUsed = stats.vram_used_gb !== undefined ? stats.vram_used_gb : 0.0;
        root.vramTotal = stats.vram_total_gb !== undefined ? stats.vram_total_gb : 8.0;
        root.vramPct = stats.vram_pct !== undefined ? stats.vram_pct : 0.0;
        root.gpuTempJunction = root.num(stats.gpu_temp_junction, -1);
        root.gpuTempMem = root.num(stats.gpu_temp_mem, -1);
        root.gpuClock = root.num(stats.gpu_clock_mhz, -1);
        root.gpuMemClock = root.num(stats.gpu_mem_clock_mhz, -1);
        root.gpuFanRpm = root.num(stats.gpu_fan_rpm, -1);
        root.gpuFanPct = root.num(stats.gpu_fan_pct, -1);
        root.gpuPower = root.num(stats.gpu_power_w, -1);
        root.gpuPowerCap = root.num(stats.gpu_power_cap_w, -1);
        root.cpuFanRpm = root.num(stats.cpu_fan_rpm, -1);

        // Disks (ListModel roles must always have a value, so missing numbers become -1)
        var diskItems = [];
        var diskList = stats.disks || [];
        for (var d = 0; d < diskList.length; d++) {
            diskItems.push({
                key: String(diskList[d].key),
                name: String(diskList[d].name),
                temp: root.num(diskList[d].temp, -1),
                usedGb: root.num(diskList[d].used_gb, 0),
                totalGb: root.num(diskList[d].total_gb, 0),
                pct: root.num(diskList[d].pct, 0)
            });
        }
        root.syncModel(diskModel, diskItems);
        root.netDownSpeed = stats.net_down_formatted !== undefined ? stats.net_down_formatted : "0 B/s";
        root.netUpSpeed = stats.net_up_formatted !== undefined ? stats.net_up_formatted : "0 B/s";

        var downVal = stats.net_down_speed || 0.0;
        var upVal = stats.net_up_speed || 0.0;

        // Use slice() to create a copy of the array so QML binding detects reference change
        var downHist = root.netDownHistory.slice();
        downHist.push(downVal);
        if (downHist.length > 30) downHist.shift();
        root.netDownHistory = downHist;

        var upHist = root.netUpHistory.slice();
        upHist.push(upVal);
        if (upHist.length > 30) upHist.shift();
        root.netUpHistory = upHist;
    }

    Component.onCompleted: {
        dbusSource.fetch();
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 280
        // Preferred height fits every visible card; if the widget is made shorter the content scrolls
        Layout.minimumHeight: 200
        Layout.preferredWidth: 320
        Layout.preferredHeight: mainColumn.implicitHeight + 28

        // One "Label: value" cell of the GPU details grid
        component InfoCell: RowLayout {
            property string label: ""
            property string value: ""
            Layout.fillWidth: true
            spacing: 5

            Text {
                text: parent.label
                color: "#a0aec0"
                font.pixelSize: 11
                font.family: "Noto Sans, Arial, sans-serif"
            }
            Text {
                text: parent.value
                color: "#ffffff"
                font.bold: true
                font.pixelSize: 11
                font.family: "Noto Sans, Arial, sans-serif"
            }
        }

        // Custom Glassmorphic background container
        Rectangle {
            id: mainContainer
            anchors.fill: parent
            color: Qt.rgba(0.08, 0.11, 0.16, 0.22) // High transparency (0.42 -> 0.22)
            radius: 14
            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.12) // Delicate border highlight
            border.width: 1

            // Cyberpunk micro-glow inner border
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                color: "transparent"
                radius: 13
                border.color: Qt.rgba(0.0, 0.94, 1.0, 0.04)
                border.width: 1
            }
        }

        // Widget UI Column Layout
        // Scrollable area: if the widget is shorter than its cards, scroll with the mouse wheel
        Flickable {
            id: scrollArea
            anchors.fill: parent
            anchors.margins: 14
            contentWidth: width
            contentHeight: mainColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: mainColumn
            width: scrollArea.width
            spacing: 10

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                
                Text {
                    text: "System Monitor"
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.weight: Font.Light
                    font.family: "Inter, Outfit, Noto Sans, Helvetica Neue, Arial, sans-serif"
                    Layout.fillWidth: true
                }
                
                Text {
                    text: "⚙" // Unicode Cog Icon
                    color: "#a0aec0"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignRight
                    
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.color = "#00f0ff"
                        onExited: parent.color = "#a0aec0"
                        onClicked: {
                            // Open the widget settings
                            var configureAction = Plasmoid.internalAction("configure");
                            if (configureAction) configureAction.trigger();
                        }
                    }
                }
            }

            // Divider Line
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1.0, 1.0, 1.0, 0.08)
            }

            // 1. Network Card
            Rectangle {
                visible: Plasmoid.configuration.showNetwork
                Layout.fillWidth: true
                Layout.preferredHeight: 145
                color: Qt.rgba(1.0, 1.0, 1.0, 0.02)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.width: 1
                radius: 8
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Kirigami.Icon {
                            source: "network-wired"
                            implicitWidth: 14
                            implicitHeight: 14
                            color: "#00f0ff"
                        }
                        Text {
                            text: "NETWORK"
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Download:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                        Text {
                            text: root.netDownSpeed
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                    
                    Canvas {
                        id: downCanvas
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        property var history: root.netDownHistory
                        onHistoryChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);
                            if (history.length < 2) return;
                            var maxVal = 10 * 1024; // 10 KB/s baseline minimum scale for active waves
                            for (var i = 0; i < history.length; i++) {
                                if (history[i] > maxVal) maxVal = history[i];
                            }
                            ctx.lineWidth = 1.5;
                            ctx.strokeStyle = "#00f0ff";
                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                            grad.addColorStop(0, Qt.rgba(0.0, 0.94, 1.0, 0.15));
                            grad.addColorStop(1, Qt.rgba(0.0, 0.94, 1.0, 0.0));
                            ctx.fillStyle = grad;
                            ctx.beginPath();
                            var dx = width / (history.length - 1);
                            ctx.moveTo(0, height - (history[0] / maxVal) * (height - 4) - 2);
                            for (var j = 1; j < history.length; j++) {
                                var x = j * dx;
                                var y = height - (history[j] / maxVal) * (height - 4) - 2;
                                var prevX = (j - 1) * dx;
                                var prevY = height - (history[j - 1] / maxVal) * (height - 4) - 2;
                                ctx.bezierCurveTo(prevX + dx/2, prevY, prevX + dx/2, y, x, y);
                            }
                            ctx.stroke();
                            ctx.lineTo(width, height);
                            ctx.lineTo(0, height);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Upload:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                        Text {
                            text: root.netUpSpeed
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                    
                    Canvas {
                        id: upCanvas
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        property var history: root.netUpHistory
                        onHistoryChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);
                            if (history.length < 2) return;
                            var maxVal = 10 * 1024; // 10 KB/s baseline minimum scale for active waves
                            for (var i = 0; i < history.length; i++) {
                                if (history[i] > maxVal) maxVal = history[i];
                            }
                            ctx.lineWidth = 1.5;
                            ctx.strokeStyle = "#00f0ff";
                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                            grad.addColorStop(0, Qt.rgba(0.0, 0.94, 1.0, 0.15));
                            grad.addColorStop(1, Qt.rgba(0.0, 0.94, 1.0, 0.0));
                            ctx.fillStyle = grad;
                            ctx.beginPath();
                            var dx = width / (history.length - 1);
                            ctx.moveTo(0, height - (history[0] / maxVal) * (height - 4) - 2);
                            for (var j = 1; j < history.length; j++) {
                                var x = j * dx;
                                var y = height - (history[j] / maxVal) * (height - 4) - 2;
                                var prevX = (j - 1) * dx;
                                var prevY = height - (history[j - 1] / maxVal) * (height - 4) - 2;
                                ctx.bezierCurveTo(prevX + dx/2, prevY, prevX + dx/2, y, x, y);
                            }
                            ctx.stroke();
                            ctx.lineTo(width, height);
                            ctx.lineTo(0, height);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                }
            }

            // 2. CPU Card
            Rectangle {
                visible: Plasmoid.configuration.showCpu
                Layout.fillWidth: true
                Layout.preferredHeight: root.cpuFanRpm >= 0 ? 124 : 100
                color: Qt.rgba(1.0, 1.0, 1.0, 0.02)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.width: 1
                radius: 8
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Kirigami.Icon {
                            source: "cpu"
                            implicitWidth: 14
                            implicitHeight: 14
                            color: "#00f0ff"
                        }
                        Text {
                            text: "CPU"
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Usage:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.preferredWidth: 40
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            spacing: 3
                            
                            Repeater {
                                model: 20
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 1.5
                                    color: index < Math.round((root.cpuUsage / 100.0) * 20)
                                           ? "#00f0ff"
                                           : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }
                        
                        Text {
                            text: Math.round(root.cpuUsage) + "%"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 35
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Temp:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.preferredWidth: 40
                        }
                        
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                radius: 3
                            }
                            
                            Rectangle {
                                width: Math.max(0, parent.width * (Math.min(100.0, root.cpuTemp) / 100.0))
                                height: parent.height
                                radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#00f0ff" } // Cyan
                                    GradientStop { position: 0.7; color: "#ff9f00" } // Orange
                                    GradientStop { position: 1.0; color: "#ff007f" } // Red/Pink
                                }
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                        
                        Text {
                            text: Math.round(root.cpuTemp) + "°C"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 35
                        }
                    }

                    // CPU fan (only when a CPU fan was found)
                    RowLayout {
                        visible: root.cpuFanRpm >= 0
                        Layout.fillWidth: true
                        Text {
                            text: "Fan:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.preferredWidth: 40
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(root.cpuFanRpm) + " RPM"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                }
            }

            // 3. RAM Card
            Rectangle {
                visible: Plasmoid.configuration.showRam
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: Qt.rgba(1.0, 1.0, 1.0, 0.02)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.width: 1
                radius: 8
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Kirigami.Icon {
                            source: "memory"
                            implicitWidth: 14
                            implicitHeight: 14
                            color: "#00f0ff"
                        }
                        Text {
                            text: "RAM"
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Usage: " + root.ramUsed.toFixed(1) + " GB / " + root.ramTotal.toFixed(0) + " GB"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                        Text {
                            text: Math.round(root.ramPct) + "%"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        spacing: 2
                        
                        Repeater {
                            model: 26
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 1.5
                                color: index < Math.round((root.ramPct / 100.0) * 26)
                                       ? "#00f0ff"
                                       : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }
                }
            }

            // 4. GPU Card
            Rectangle {
                visible: Plasmoid.configuration.showGpu
                Layout.fillWidth: true
                Layout.preferredHeight: root.gpuExpanded ? 156 : 100
                color: Qt.rgba(1.0, 1.0, 1.0, 0.02)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.width: 1
                radius: 8
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Kirigami.Icon {
                            source: "video-card"
                            implicitWidth: 14
                            implicitHeight: 14
                            color: "#00f0ff"
                        }
                        Text {
                            text: "GPU"
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }

                        Item { Layout.fillWidth: true }

                        // "More / Less" button for the extra GPU details
                        Text {
                            text: root.gpuExpanded ? "▴ Less" : "▾ More"
                            color: toggleArea.containsMouse ? "#00f0ff" : "#a0aec0"
                            font.pixelSize: 10
                            font.family: "Noto Sans, Arial, sans-serif"

                            MouseArea {
                                id: toggleArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.gpuExpanded = !root.gpuExpanded
                            }
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Usage:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.preferredWidth: 40
                        }
                        
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            spacing: 3
                            
                            Repeater {
                                model: 20
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 1.5
                                    color: index < Math.round((root.gpuUsage / 100.0) * 20)
                                           ? "#00f0ff"
                                           : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }
                        
                        Text {
                            text: Math.round(root.gpuUsage) + "%"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 35
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Temp:"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.preferredWidth: 40
                        }
                        
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                radius: 3
                            }
                            
                            Rectangle {
                                width: Math.max(0, parent.width * (Math.min(100.0, root.gpuTemp) / 100.0))
                                height: parent.height
                                radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#00f0ff" }
                                    GradientStop { position: 0.7; color: "#ff9f00" }
                                    GradientStop { position: 1.0; color: "#ff007f" }
                                }
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                        
                        Text {
                            text: Math.round(root.gpuTemp) + "°C"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 35
                        }
                    }

                    // Extra details, visible only after pressing "More"
                    Rectangle {
                        visible: root.gpuExpanded
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.rgba(1.0, 1.0, 1.0, 0.08)
                    }

                    GridLayout {
                        visible: root.gpuExpanded
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 4

                        InfoCell { label: "Junction:"; value: root.fmtValue(root.gpuTempJunction, 0, "°C") }
                        InfoCell { label: "Mem temp:"; value: root.fmtValue(root.gpuTempMem, 0, "°C") }
                        InfoCell { label: "Clock:"; value: root.fmtValue(root.gpuClock, 0, " MHz") }
                        InfoCell { label: "Mem clock:"; value: root.fmtValue(root.gpuMemClock, 0, " MHz") }
                        InfoCell { label: "Fan:"; value: root.fanText() }
                        InfoCell { label: "Power:"; value: root.powerText() }
                    }
                }
            }

            // 5. VRAM Card
            Rectangle {
                visible: Plasmoid.configuration.showVram
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: Qt.rgba(1.0, 1.0, 1.0, 0.02)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.width: 1
                radius: 8
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Kirigami.Icon {
                            source: "video-card"
                            implicitWidth: 14
                            implicitHeight: 14
                            color: "#00f0ff"
                        }
                        Text {
                            text: "VRAM"
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Usage: " + root.vramUsed.toFixed(1) + " GB / " + root.vramTotal.toFixed(0) + " GB"
                            color: "#a0aec0"
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                        Text {
                            text: Math.round(root.vramPct) + "%"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        spacing: 3
                        
                        Repeater {
                            model: 20
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 1.5
                                color: index < Math.round((root.vramPct / 100.0) * 20)
                                       ? "#00f0ff"
                                       : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }
                    }
                }
            }

            // 6. Disks Card (one compact block per physical disk with a mounted filesystem)
            Rectangle {
                visible: Plasmoid.configuration.showDisks && diskModel.count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: diskColumn.implicitHeight + 20
                color: Qt.rgba(1.0, 1.0, 1.0, 0.02)
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.width: 1
                radius: 8

                ColumnLayout {
                    id: diskColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Kirigami.Icon {
                            source: "drive-harddisk"
                            implicitWidth: 14
                            implicitHeight: 14
                            color: "#00f0ff"
                        }
                        Text {
                            text: "DISKS"
                            color: "#00f0ff"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "Noto Sans, Arial, sans-serif"
                        }
                    }

                    Repeater {
                        model: diskModel

                        ColumnLayout {
                            id: diskItem
                            property real pctValue: model.pct
                            Layout.fillWidth: true
                            spacing: 4

                            // Row 1: model name | used / total · temperature
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: model.name
                                    color: "#a0aec0"
                                    elide: Text.ElideRight
                                    font.pixelSize: 11
                                    font.family: "Noto Sans, Arial, sans-serif"
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: root.fmtSize(model.usedGb) + " / " + root.fmtSize(model.totalGb)
                                          + (model.temp >= 0 ? " · " + Math.round(model.temp) + "°C" : "")
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "Noto Sans, Arial, sans-serif"
                                    Layout.alignment: Qt.AlignRight
                                }
                            }

                            // Row 2: usage bar | percent
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Repeater {
                                    model: 20
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 8
                                        radius: 1.5
                                        color: index < Math.round((diskItem.pctValue / 100.0) * 20)
                                               ? "#00f0ff"
                                               : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                Text {
                                    text: Math.round(diskItem.pctValue) + "%"
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "Noto Sans, Arial, sans-serif"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 35
                                    Layout.leftMargin: 4
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
