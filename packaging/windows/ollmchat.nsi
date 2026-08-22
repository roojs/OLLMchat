; OLLMchat Windows installer (NSIS)
;
; Builds versioned OLLMchat-<version>-Setup.exe from a staged portable tree
; (exe + GTK DLLs + WebView2Loader). Staging is an intermediate for NSIS —
; the release asset is only the Setup.exe.
;
;   ./scripts/ci/windows-package-nsis.sh

!include "MUI2.nsh"

!define PRODUCT_NAME "OLLMchat"
!define PRODUCT_PUBLISHER "roojs"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\OLLMchat"
!define INSTALL_REG_KEY "Software\roojs\OLLMchat"

Name "${PRODUCT_NAME}"

!ifndef OUTFILE
  !define OUTFILE "dist-windows\OLLMchat-Setup.exe"
!endif
OutFile "${OUTFILE}"

InstallDir "$LOCALAPPDATA\OLLMchat"
InstallDirRegKey HKCU "${INSTALL_REG_KEY}" "InstallDir"

RequestExecutionLevel user
Unicode true
ShowInstDetails nevershow

!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.0.0"
!endif
!ifndef INST_SRC
  !define INST_SRC "dist-windows\OLLMchat"
!endif
!ifndef MUI_ICON
  !define MUI_ICON "pixmaps\org.roojs.ollmchat.ico"
!endif
!ifndef MUI_UNICON
  !define MUI_UNICON "${MUI_ICON}"
!endif

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ClearErrors
  ExecWait 'taskkill /F /IM OLLMchat.exe' $0
  ExecWait 'taskkill /F /IM ollmfilesd.exe' $0
  Sleep 500
FunctionEnd

Section "OLLMchat" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${INST_SRC}\*.*"

  WriteRegStr HKCU "${INSTALL_REG_KEY}" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" \
    "$INSTDIR\OLLMchat.exe" "" "$INSTDIR\OLLMchat.exe" 0
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk" \
    "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "${INSTALL_REG_KEY}"
SectionEnd
