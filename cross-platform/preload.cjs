const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('nfc', {
  getState: () => ipcRenderer.invoke('state:get'),
  onState: callback => {
    const listener = (_, state) => callback(state);
    ipcRenderer.on('state:changed', listener);
    return () => ipcRenderer.removeListener('state:changed', listener);
  },
  onOverlayUnlock: callback => {
    const listener = (_, unlocked) => callback(unlocked);
    ipcRenderer.on('overlay:unlock', listener);
    return () => ipcRenderer.removeListener('overlay:unlock', listener);
  },
  listContext: () => ipcRenderer.invoke('context:list'),
  updateSettings: patch => ipcRenderer.invoke('settings:update', patch),
  startSession: payload => ipcRenderer.invoke('session:start', payload),
  togglePause: () => ipcRenderer.invoke('session:pause-toggle'),
  stopSession: () => ipcRenderer.invoke('session:stop'),
  showOverlay: () => ipcRenderer.invoke('overlay:show'),
  hideOverlay: () => ipcRenderer.invoke('overlay:hide'),
  setOverlayInteractive: interactive => ipcRenderer.invoke('overlay:set-interactive', interactive),
  showDashboard: () => ipcRenderer.invoke('window:show'),
  minimize: () => ipcRenderer.invoke('window:minimize'),
  close: () => ipcRenderer.invoke('window:close'),
  clearHistory: () => ipcRenderer.invoke('history:clear'),
  exportData: () => ipcRenderer.invoke('data:export'),
  importData: () => ipcRenderer.invoke('data:import'),
  configureSync: config => ipcRenderer.invoke('sync:configure', config),
  runSync: direction => ipcRenderer.invoke('sync:run', direction)
});
