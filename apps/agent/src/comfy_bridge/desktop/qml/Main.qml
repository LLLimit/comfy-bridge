import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1280
    height: 820
    minimumWidth: 1100
    minimumHeight: 720
    visible: true
    title: "Comfy Bridge Control Center"
    color: "#080c14"
    font.family: "Segoe UI Variable"

    readonly property color pageColor: "#080c14"
    readonly property color sidebarColor: "#0d1320"
    readonly property color panelColor: "#121a29"
    readonly property color panelRaised: "#182235"
    readonly property color borderColor: "#263249"
    readonly property color textColor: "#f5f7fb"
    readonly property color mutedColor: "#8b98ad"
    readonly property color accentColor: "#8b5cf6"
    readonly property color cyanColor: "#43c9e8"
    readonly property color greenColor: "#3dd6a0"
    readonly property color redColor: "#ff6b81"
    readonly property color yellowColor: "#f7c75b"
    property int currentPage: 0

    component ModernButton: Button {
        id: control
        property color fillColor: window.panelRaised
        property color hoverColor: Qt.lighter(fillColor, 1.16)
        property color textTint: window.textColor
        implicitHeight: 42
        implicitWidth: Math.max(116, label.implicitWidth + 32)
        padding: 0
        contentItem: Text {
            id: label
            text: control.text
            color: control.textTint
            font.pixelSize: 13
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 10
            color: control.down ? Qt.darker(control.fillColor, 1.1)
                                : control.hovered ? control.hoverColor : control.fillColor
            border.width: control.fillColor === window.panelRaised ? 1 : 0
            border.color: window.borderColor
            Behavior on color { ColorAnimation { duration: 130 } }
        }
    }

    component Panel: Rectangle {
        color: window.panelColor
        radius: 16
        border.width: 1
        border.color: window.borderColor
    }

    component ConfigField: ColumnLayout {
        id: fieldRoot
        property string label: ""
        property alias text: input.text
        property string placeholder: ""
        property bool browse: false
        property bool password: false
        property bool reveal: false
        signal browseRequested()
        spacing: 7
        Layout.fillWidth: true
        Text {
            text: fieldRoot.label
            color: window.mutedColor
            font.pixelSize: 12
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: input
                Layout.fillWidth: true
                implicitHeight: 42
                color: window.textColor
                placeholderText: fieldRoot.placeholder
                placeholderTextColor: "#59677e"
                echoMode: fieldRoot.password && !fieldRoot.reveal ? TextInput.Password : TextInput.Normal
                selectByMouse: true
                leftPadding: 13
                rightPadding: 13
                background: Rectangle {
                    radius: 9
                    color: "#0b111d"
                    border.width: input.activeFocus ? 2 : 1
                    border.color: input.activeFocus ? window.accentColor : window.borderColor
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }
            }
            ModernButton {
                visible: fieldRoot.password
                text: fieldRoot.reveal ? "隐藏" : "显示"
                implicitWidth: 64
                onClicked: fieldRoot.reveal = !fieldRoot.reveal
            }
            ModernButton {
                visible: fieldRoot.browse
                text: "浏览"
                implicitWidth: 64
                onClicked: fieldRoot.browseRequested()
            }
        }
    }

    component StatusCard: Panel {
        id: card
        property string keyName: ""
        property string badge: ""
        property string title: ""
        property string description: ""
        property var status: backend.statusData[keyName] || ({"label": "等待检测", "tone": "muted"})
        implicitHeight: 150
        Layout.fillWidth: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            RowLayout {
                spacing: 10
                Rectangle {
                    width: 34
                    height: 34
                    radius: 9
                    color: "#202c42"
                    Text {
                        anchors.centerIn: parent
                        text: card.badge
                        color: window.cyanColor
                        font.bold: true
                        font.pixelSize: 13
                    }
                }
                Text {
                    text: card.title
                    color: window.textColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                spacing: 8
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: card.status.tone === "online" ? window.greenColor
                         : card.status.tone === "checking" ? window.yellowColor
                         : card.status.tone === "muted" ? window.mutedColor : window.redColor
                    SequentialAnimation on opacity {
                        running: card.status.tone === "checking"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 450 }
                        NumberAnimation { to: 1.0; duration: 450 }
                    }
                }
                Text {
                    text: card.status.label
                    color: card.status.tone === "online" ? window.greenColor
                         : card.status.tone === "checking" ? window.yellowColor
                         : card.status.tone === "muted" ? window.mutedColor : window.redColor
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
            }
            Text {
                text: card.description
                color: window.mutedColor
                font.pixelSize: 11
            }
        }
    }

    component GaugeButton: Item {
        id: gauge
        width: 58
        height: 58
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: gaugeMouse.containsMouse ? window.panelRaised : window.panelColor
            border.width: 1
            border.color: backend.checking ? window.yellowColor : window.borderColor
            Behavior on color { ColorAnimation { duration: 130 } }
            Behavior on border.color { ColorAnimation { duration: 130 } }
        }
        Canvas {
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = window.cyanColor
                ctx.lineWidth = 3
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(29, 31, 14, Math.PI * 1.12, Math.PI * 1.88)
                ctx.stroke()
                for (let i = 0; i < 5; i++) {
                    const angle = Math.PI * (1.15 + i * 0.175)
                    ctx.beginPath()
                    ctx.moveTo(29 + Math.cos(angle) * 10, 31 + Math.sin(angle) * 10)
                    ctx.lineTo(29 + Math.cos(angle) * 13, 31 + Math.sin(angle) * 13)
                    ctx.stroke()
                }
            }
        }
        Item {
            id: needle
            width: 26
            height: 26
            anchors.centerIn: parent
            rotation: -52
            transformOrigin: Item.Center
            Rectangle {
                width: 2
                height: 12
                radius: 1
                color: window.textColor
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
            }
            Rectangle {
                width: 5
                height: 5
                radius: 3
                color: window.textColor
                anchors.centerIn: parent
            }
            RotationAnimation on rotation {
                running: backend.checking
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 720
                onRunningChanged: if (!running) needle.rotation = -52
            }
        }
        MouseArea {
            id: gaugeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !backend.checking
            onClicked: backend.refreshStatus()
        }
        ToolTip.visible: gaugeMouse.containsMouse
        ToolTip.text: backend.checking ? "正在检测" : "检测全部连接"
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 224
            Layout.fillHeight: true
            color: window.sidebarColor
            border.width: 0
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.topMargin: 10
                    Layout.bottomMargin: 28
                    spacing: 11
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 11
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#9d79fa" }
                            GradientStop { position: 1; color: "#6545d8" }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "CB"
                            color: "white"
                            font.bold: true
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "Comfy Bridge"
                            color: window.textColor
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "CONTROL CENTER"
                            color: window.mutedColor
                            font.pixelSize: 8
                            font.letterSpacing: 1.2
                        }
                    }
                }
                Repeater {
                    model: [
                        {"icon": "◈", "title": "控制中心"},
                        {"icon": "⚙", "title": "服务配置"},
                        {"icon": "≡", "title": "运行日志"}
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 11
                        color: window.currentPage === index ? "#202b42" : navMouse.containsMouse ? "#151e2e" : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 12
                            spacing: 13
                            Text {
                                text: modelData.icon
                                color: window.currentPage === index ? window.cyanColor : window.mutedColor
                                font.pixelSize: 17
                            }
                            Text {
                                text: modelData.title
                                color: window.currentPage === index ? window.textColor : window.mutedColor
                                font.pixelSize: 13
                                font.weight: window.currentPage === index ? Font.DemiBold : Font.Normal
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                visible: window.currentPage === index
                                width: 3
                                height: 18
                                radius: 2
                                color: window.accentColor
                            }
                        }
                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                window.currentPage = index
                                if (index === 2) backend.refreshLogs()
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.leftMargin: 8
                    Layout.bottomMargin: 8
                    text: "AGENT  v0.2.0\nLOCAL-FIRST · OPEN SOURCE"
                    color: "#58657a"
                    font.pixelSize: 9
                    lineHeight: 1.45
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                Layout.leftMargin: 30
                Layout.rightMargin: 30
                ColumnLayout {
                    spacing: 4
                    Text {
                        text: window.currentPage === 0 ? "控制中心"
                            : window.currentPage === 1 ? "服务配置" : "运行日志"
                        color: window.textColor
                        font.pixelSize: 26
                        font.weight: Font.Bold
                    }
                    Text {
                        text: window.currentPage === 0 ? "管理 Bridge、ComfyUI 与公网连接"
                            : window.currentPage === 1 ? "集中管理 Agent、工作流与 FRP 参数"
                            : "查看最近的服务运行与错误信息"
                        color: window.mutedColor
                        font.pixelSize: 12
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: summaryText.implicitWidth + 30
                    implicitHeight: 38
                    radius: 11
                    color: window.panelColor
                    border.width: 1
                    border.color: window.borderColor
                    Text {
                        id: summaryText
                        anchors.centerIn: parent
                        text: backend.summary
                        color: backend.checking ? window.yellowColor : window.cyanColor
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: window.currentPage

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        anchors.bottomMargin: 26
                        spacing: 16
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "服务状态"
                                color: window.textColor
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "点击仪表盘重新检测"
                                color: window.mutedColor
                                font.pixelSize: 11
                                Layout.leftMargin: 8
                            }
                            Item { Layout.fillWidth: true }
                            GaugeButton { }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 10
                            StatusCard { keyName: "agent"; badge: "B"; title: "Bridge 服务"; description: "手机控制 API" }
                            StatusCard { keyName: "comfy"; badge: "C"; title: "ComfyUI"; description: "生成服务后端" }
                            StatusCard { keyName: "frp"; badge: "F"; title: "FRP 隧道"; description: "公网端口映射" }
                            StatusCard { keyName: "public"; badge: "P"; title: "公网入口"; description: "手机远程访问" }
                        }
                        Panel {
                            Layout.fillWidth: true
                            implicitHeight: 114
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 10
                                ColumnLayout {
                                    spacing: 3
                                    Text { text: "服务控制"; color: window.textColor; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { text: "启动前会自动保存当前配置"; color: window.mutedColor; font.pixelSize: 11 }
                                }
                                Item { Layout.fillWidth: true }
                                ModernButton { text: "仅启动 Bridge"; onClicked: backend.startAgent(settingsPage.collect()) }
                                ModernButton { text: "仅启动 FRP"; onClicked: backend.startFrp(settingsPage.collect()) }
                                ModernButton { text: "停止服务"; fillColor: "#5d2b39"; onClicked: backend.stopAll() }
                                ModernButton { text: "启动 Bridge + FRP"; fillColor: window.accentColor; onClicked: backend.startAll(settingsPage.collect()) }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12
                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 20
                                    spacing: 10
                                    Text { text: "连接信息"; color: window.textColor; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { text: "本机 Agent"; color: window.mutedColor; font.pixelSize: 10 }
                                    Text { text: backend.configData.localAgentUrl; color: window.cyanColor; font.pixelSize: 13 }
                                    Text { text: "手机公网地址"; color: window.mutedColor; font.pixelSize: 10; Layout.topMargin: 5 }
                                    Text { text: backend.configData.resolvedPublicUrl; color: window.textColor; font.pixelSize: 13 }
                                    Item { Layout.fillHeight: true }
                                    Text { text: "FRP 映射  ·  " + backend.configData.frpMapping; color: window.mutedColor; font.pixelSize: 11 }
                                }
                            }
                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 20
                                    spacing: 10
                                    Text { text: "手机设备密钥"; color: window.textColor; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { text: "密钥只保存在电脑本地"; color: window.mutedColor; font.pixelSize: 10 }
                                    TextField {
                                        id: deviceTokenField
                                        Layout.fillWidth: true
                                        text: backend.deviceToken
                                        readOnly: true
                                        echoMode: showDeviceToken.checked ? TextInput.Normal : TextInput.Password
                                        color: window.textColor
                                        background: Rectangle { radius: 9; color: "#0b111d"; border.color: window.borderColor }
                                    }
                                    RowLayout {
                                        CheckBox { id: showDeviceToken; text: "显示密钥" }
                                        Item { Layout.fillWidth: true }
                                        ModernButton { text: "重新生成"; onClicked: backend.regenerateDeviceToken() }
                                        ModernButton { text: "复制密钥"; fillColor: "#20536a"; onClicked: backend.copyDeviceToken() }
                                    }
                                    Item { Layout.fillHeight: true }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: settingsPage
                    function load() {
                        const c = backend.configData
                        host.text = c.host; port.text = c.port; comfyUrl.text = c.comfyUrl
                        dataDir.text = c.dataDir; workflowDir.text = c.workflowDir; comfyLog.text = c.comfyLogPath
                        debug.checked = c.debug; frpEnabled.checked = c.frpEnabled
                        frpExe.text = c.frpExecutable; frpConfig.text = c.frpConfigPath
                        frpServer.text = c.frpServerAddr; frpServerPort.text = c.frpServerPort
                        frpToken.text = c.frpAuthToken; frpRemotePort.text = c.frpRemotePort
                        publicUrl.text = c.publicAgentUrl; frpTls.checked = c.frpTls
                        frpEncryption.checked = c.frpEncryption; frpCompression.checked = c.frpCompression
                    }
                    function collect() {
                        return {
                            "host": host.text, "port": port.text, "comfyUrl": comfyUrl.text,
                            "dataDir": dataDir.text, "workflowDir": workflowDir.text,
                            "comfyLogPath": comfyLog.text, "debug": debug.checked,
                            "frpEnabled": frpEnabled.checked, "frpExecutable": frpExe.text,
                            "frpConfigPath": frpConfig.text, "frpServerAddr": frpServer.text,
                            "frpServerPort": frpServerPort.text, "frpAuthToken": frpToken.text,
                            "frpRemotePort": frpRemotePort.text, "frpTls": frpTls.checked,
                            "frpEncryption": frpEncryption.checked, "frpCompression": frpCompression.checked,
                            "publicAgentUrl": publicUrl.text
                        }
                    }
                    Component.onCompleted: load()
                    Connections { target: backend; function onConfigChanged() { settingsPage.load() } }
                    ScrollView {
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        anchors.bottomMargin: 24
                        clip: true
                        contentWidth: availableWidth
                        GridLayout {
                            width: parent.width
                            columns: 2
                            columnSpacing: 14
                            rowSpacing: 14
                            Panel {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: agentFields.implicitHeight + 40
                                ColumnLayout {
                                    id: agentFields
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: 20
                                    spacing: 11
                                    Text { text: "Bridge / ComfyUI"; color: window.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }
                                    Text { text: "本地服务与工作流配置"; color: window.mutedColor; font.pixelSize: 11 }
                                    ConfigField { id: host; label: "Agent 监听地址" }
                                    ConfigField { id: port; label: "Agent 端口" }
                                    ConfigField { id: comfyUrl; label: "ComfyUI 地址" }
                                    ConfigField { id: dataDir; label: "数据目录"; browse: true; onBrowseRequested: { const p = backend.browseDirectory(text); if (p) text = p } }
                                    ConfigField { id: workflowDir; label: "工作流目录"; browse: true; onBrowseRequested: { const p = backend.browseDirectory(text); if (p) text = p } }
                                    ConfigField { id: comfyLog; label: "ComfyUI 日志文件（可留空）"; browse: true; onBrowseRequested: { const p = backend.browseFile(text); if (p) text = p } }
                                    CheckBox { id: debug; text: "启用调试日志" }
                                }
                            }
                            Panel {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: frpFields.implicitHeight + 40
                                ColumnLayout {
                                    id: frpFields
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: 20
                                    spacing: 11
                                    Text { text: "FRP 公网隧道"; color: window.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }
                                    Text { text: "远程连接与加密配置"; color: window.mutedColor; font.pixelSize: 11 }
                                    CheckBox { id: frpEnabled; text: "启用 FRP" }
                                    ConfigField { id: frpExe; label: "frpc.exe"; browse: true; onBrowseRequested: { const p = backend.browseFile(text); if (p) text = p } }
                                    ConfigField { id: frpConfig; label: "frpc.toml"; browse: true; onBrowseRequested: { const p = backend.browseFile(text); if (p) text = p } }
                                    ConfigField { id: frpServer; label: "FRP 服务器地址" }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ConfigField { id: frpServerPort; label: "控制端口"; Layout.fillWidth: true }
                                        ConfigField { id: frpRemotePort; label: "公网端口"; Layout.fillWidth: true }
                                    }
                                    ConfigField { id: frpToken; label: "FRP 验证 Token"; password: true }
                                    ConfigField { id: publicUrl; label: "手机公网地址 / 域名" }
                                    RowLayout {
                                        CheckBox { id: frpTls; text: "TLS" }
                                        CheckBox { id: frpEncryption; text: "隧道加密" }
                                        CheckBox { id: frpCompression; text: "压缩" }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                Text { text: "运行中的服务需要重启后应用新配置"; color: window.mutedColor; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                ModernButton { text: "恢复配置"; onClicked: backend.reloadConfig() }
                                ModernButton { text: "保存全部配置"; fillColor: window.accentColor; onClicked: backend.saveConfig(settingsPage.collect()) }
                            }
                        }
                    }
                }

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        anchors.bottomMargin: 24
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            ModernButton { text: "刷新日志"; fillColor: window.accentColor; onClicked: backend.refreshLogs() }
                            ModernButton { text: "打开 Bridge 日志目录"; onClicked: backend.openAgentLogDirectory() }
                            ModernButton { text: "打开 FRP 日志目录"; onClicked: backend.openFrpLogDirectory() }
                            Item { Layout.fillWidth: true }
                            Text { text: "显示最近 500 行 · 不修改原始日志"; color: window.mutedColor; font.pixelSize: 11 }
                        }
                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8
                                TabBar {
                                    id: logTabs
                                    Layout.fillWidth: true
                                    TabButton { text: "ComfyUI" }
                                    TabButton { text: "Bridge 服务" }
                                    TabButton { text: "FRP" }
                                }
                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: logTabs.currentIndex
                                    Repeater {
                                        model: ["comfy", "bridge", "frp"]
                                        ScrollView {
                                            required property string modelData
                                            TextArea {
                                                text: backend.logData[modelData] || "暂无日志"
                                                readOnly: true
                                                selectByMouse: true
                                                wrapMode: TextEdit.NoWrap
                                                color: "#d9e2f0"
                                                font.family: "Cascadia Mono"
                                                font.pixelSize: 11
                                                background: Rectangle { color: "#080d16"; radius: 10 }
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
    }

    Rectangle {
        id: toast
        width: Math.min(420, toastColumn.implicitWidth + 36)
        height: toastColumn.implicitHeight + 28
        radius: 13
        color: "#202b42"
        border.width: 1
        border.color: window.accentColor
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        opacity: 0
        visible: opacity > 0
        property string title: ""
        property string detail: ""
        Column {
            id: toastColumn
            anchors.centerIn: parent
            spacing: 4
            Text { text: toast.title; color: window.textColor; font.pixelSize: 13; font.bold: true }
            Text { text: toast.detail; color: window.mutedColor; font.pixelSize: 11; wrapMode: Text.Wrap; width: Math.min(360, implicitWidth) }
        }
        SequentialAnimation {
            id: toastAnimation
            NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 160 }
            PauseAnimation { duration: 2400 }
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 220 }
        }
    }

    Connections {
        target: backend
        function onToastRequested(title, detail) {
            toast.title = title
            toast.detail = detail
            toastAnimation.restart()
        }
    }

    onClosing: backend.shutdown()
}
