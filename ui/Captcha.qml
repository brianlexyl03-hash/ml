import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window

ApplicationWindow {
    id: applicationWindowCaptcha
    title: qsTr("Captcha")

    modality: Qt.ApplicationModal
    flags: Qt.Dialog

    property int margin: 10
    property bool kill: false
    property bool mobileLayout: Qt.platform.os === "android"

    width: mobileLayout ? 340 : columnLayoutCaptcha.implicitWidth + 2 * margin
    height: mobileLayout ? 300 : columnLayoutCaptcha.implicitHeight + 2 * margin
    minimumWidth: mobileLayout ? 300 : columnLayoutCaptcha.Layout.minimumWidth + 2 * margin
    minimumHeight: mobileLayout ? 260 : columnLayoutCaptcha.Layout.minimumHeight + 2 * margin

    signal killCaptcha(bool kill, string captcha)

    function showUICaptcha(captchaImagePath) {
        imageCaptcha.source = captchaImagePath
        textFieldCaptcha.text = ""
        show()
    }

    ColumnLayout {
        id: columnLayoutCaptcha

        anchors.fill: parent
        anchors.margins: margin
        spacing: margin

        focus: true

        Image {
            id: imageCaptcha
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: mobileLayout ? 300 : implicitWidth
            Layout.maximumHeight: mobileLayout ? 180 : implicitHeight
            fillMode: Image.PreserveAspectFit
        }

        GridLayout {
            columns: mobileLayout ? 2 : 4
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

            Label {
                text: qsTr("Captcha: ")
            }

            TextField {
                id: textFieldCaptcha

                Layout.minimumWidth: mobileLayout ? 100 : 160
                Layout.fillWidth: mobileLayout

                selectByMouse: true
            }

            Button {
                id: buttonCaptchaConfirm
                text: qsTr("Confirm")

                onClicked: {
                    applicationWindowCaptcha.kill = true
                    close()
                }
            }

            Button {
                id: buttonCaptchaCancel
                text: qsTr("Cancel")

                onClicked: {
                    applicationWindowCaptcha.kill = false
                    close()
                }
            }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                buttonCaptchaConfirm.clicked()
            } else if (event.key === Qt.Key_Escape) {
                buttonCaptchaCancel.clicked()
            }
        }
    }

    onClosing: {
        killCaptcha(kill, textFieldCaptcha.text.trim())
    }
}
