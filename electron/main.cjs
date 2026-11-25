const { app, BrowserWindow, ipcMain, dialog } = require('electron')
const { spawn } = require('node:child_process')
const path = require('node:path')
const fs = require('node:fs')

function createWindow() {
  const win = new BrowserWindow({
    width: 1320, height: 920, minWidth: 980, minHeight: 700,
    backgroundColor: '#0d0e11',
    title: 'Ghosty Terminal Studio',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  })
  win.loadFile(path.join(__dirname, '../dist/index.html'))
}

ipcMain.handle('ghosty:apply', async (_event, settings) => {
  if (process.platform !== 'win32') return { ok: false, message: 'Apply setup is available in the Windows desktop app.' }
  const scriptPath = path.join(process.resourcesPath, 'scripts', 'apply-setup.ps1')
  if (!fs.existsSync(scriptPath)) return { ok: false, message: 'Setup script is missing from this app package.' }
  const { response } = await dialog.showMessageBox({
    type: 'warning', buttons: ['Apply changes', 'Cancel'], defaultId: 1, cancelId: 1,
    title: 'Apply Ghosty setup?',
    message: 'Ghosty will install the selected command-line tools and update your Windows Terminal and PowerShell configuration.',
    detail: 'Your Windows Terminal settings are backed up before editing. WinGet may show its own install prompts.',
  })
  if (response !== 0) return { ok: false, cancelled: true, message: 'No changes were made.' }
  const configPath = path.join(app.getPath('temp'), `ghosty-${Date.now()}.json`)
  fs.writeFileSync(configPath, JSON.stringify(settings), 'utf8')
  return await new Promise((resolve) => {
    const child = spawn('powershell.exe', ['-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, '-ConfigPath', configPath], { windowsHide: true })
    let stdout = '', stderr = ''
    child.stdout.on('data', b => { stdout += b.toString() })
    child.stderr.on('data', b => { stderr += b.toString() })
    child.on('error', err => { try { fs.unlinkSync(configPath) } catch {} resolve({ ok: false, message: err.message }) })
    child.on('close', code => {
      try { fs.unlinkSync(configPath) } catch {}
      resolve(code === 0 ? { ok: true, message: stdout.trim() || 'Setup applied. Open a new PowerShell window to use it.' } : { ok: false, message: (stderr || stdout || `Setup failed (${code}).`).trim() })
    })
  })
})

app.whenReady().then(() => {
  createWindow()
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
})
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
