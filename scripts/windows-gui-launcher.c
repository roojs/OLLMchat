#define WIN32_LEAN_AND_MEAN
#include <windows.h>

int main(void) {
	wchar_t dir[MAX_PATH];
	DWORD n = GetModuleFileNameW(NULL, dir, MAX_PATH);
	if (n == 0 || n >= MAX_PATH) return 1;
	while (n > 0 && dir[n - 1] != L'\\') n--;
	if (n > 0) dir[n - 1] = 0;
	wchar_t cmd[1024];
	lstrcpyW(cmd, L"cmd.exe /c \"\"");
	lstrcatW(cmd, dir);
	lstrcatW(cmd, L"\\OLLMchat.bat\"\"");
	STARTUPINFOW si;
	ZeroMemory(&si, sizeof(si));
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESHOWWINDOW;
	si.wShowWindow = SW_HIDE;
	PROCESS_INFORMATION pi;
	ZeroMemory(&pi, sizeof(pi));
	if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, dir, &si, &pi))
		return 1;
	CloseHandle(pi.hThread);
	CloseHandle(pi.hProcess);
	return 0;
}
