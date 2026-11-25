const { contextBridge, ipcRenderer } = require('electron')
contextBridge.exposeInMainWorld('ghosty', {
  isDesktop: true,
  applySetup: (settings) => ipcRenderer.invoke('ghosty:apply', settings),
})
