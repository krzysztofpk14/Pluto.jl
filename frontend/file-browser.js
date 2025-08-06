class PlutoFileBrowser {
    constructor() {
        this.currentUser = null;
        this.fileTree = null;
        this.isInitialized = false;
        this.client = null; // Optional for WebSocket communication
        
        this.init();
    }
    
    init() {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.initialize());
        } else {
            this.initialize();
        }
    }
    
    async initialize() {
        try {
            await this.getCurrentUser();
            this.setupEventListeners();
            await this.loadFileTree();
            
            this.isInitialized = true;
            console.log('Pluto File Browser initialized using REST API');
        } catch (error) {
            console.error('Failed to initialize file browser:', error);
            this.setupEventListeners();
            // Show empty tree on error
            this.fileTree = this.createEmptyFileTree();
            this.renderFileTree();
        }
    }

    // Utility methods
    createEmptyFileTree() {
        return {
            name: 'root',
            type: 'directory',
            path: '',
            contents: []
        };
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 B';
        
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    }

    setupResizeHandle() {
        const resizeHandle = document.getElementById('resize-handle');
        const fileBrowser = document.getElementById('pluto-file-browser');
        
        if (!resizeHandle || !fileBrowser) return;
        
        let isResizing = false;
        let startX = 0;
        let startWidth = 0;
        
        // Store width in localStorage for persistence
        const savedWidth = localStorage.getItem('pluto-file-browser-width');
        if (savedWidth) {
            fileBrowser.style.width = savedWidth + 'px';
        }
        
        resizeHandle.addEventListener('mousedown', (e) => {
            isResizing = true;
            startX = e.clientX;
            startWidth = parseInt(getComputedStyle(fileBrowser).width, 10);
            
            // Add visual feedback
            document.body.style.cursor = 'col-resize';
            document.body.style.userSelect = 'none';
            
            // Prevent text selection during resize
            e.preventDefault();
        });
        
        document.addEventListener('mousemove', (e) => {
            if (!isResizing) return;
            
            const width = startWidth + e.clientX - startX;
            const minWidth = 200;
            const maxWidth = Math.min(600, window.innerWidth * 0.5);
            
            const constrainedWidth = Math.max(minWidth, Math.min(maxWidth, width));
            
            fileBrowser.style.width = constrainedWidth + 'px';
            
            // Update CSS custom property for potential use elsewhere
            document.documentElement.style.setProperty('--file-browser-width', constrainedWidth + 'px');
        });
        
        document.addEventListener('mouseup', () => {
            if (isResizing) {
                isResizing = false;
                
                // Remove visual feedback
                document.body.style.cursor = '';
                document.body.style.userSelect = '';
                
                // Save width to localStorage
                const currentWidth = parseInt(getComputedStyle(fileBrowser).width, 10);
                localStorage.setItem('pluto-file-browser-width', currentWidth);
            }
        });
        
        // Handle double-click to reset to default width
        resizeHandle.addEventListener('dblclick', () => {
            const defaultWidth = 300;
            fileBrowser.style.width = defaultWidth + 'px';
            localStorage.setItem('pluto-file-browser-width', defaultWidth);
            document.documentElement.style.setProperty('--file-browser-width', defaultWidth + 'px');
        });
    }
    
    // TODO: Implement curret user
    async getCurrentUser() {
        this.currentUser = { username: 'default', id: 'default' };
    }
    
    setupEventListeners() {
        // Only setup event listeners for elements that exist
        this.setupToolbarButtons();
        this.setupContextMenus();
        this.setupPopupDialogs();
        this.setupResizeHandle();
        
        // Search functionality
        const searchInput = document.getElementById('searchInput');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => this.filterFiles(e.target.value));
        }
        
        // Close context menus when clicking elsewhere
        document.addEventListener('click', (e) => {
            if (!e.target.closest('.context-menu')) {
                this.hideAllContextMenus();
            }
        });
    }
    
    setupToolbarButtons() {
        const refreshBtn = document.getElementById('refresh-btn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => this.loadFileTree());
        }
        
        const newNotebookBtn = document.getElementById('new-notebook-btn');
        if (newNotebookBtn) {
            newNotebookBtn.addEventListener('click', () => this.createNewNotebook());
        }
    }
    
    setupContextMenus() {
        // File context menu
        const fileMenu = document.getElementById('fileContextMenu');
        if (fileMenu) {
            const openBtn = fileMenu.querySelector('.open');
            const shutdownBtn = fileMenu.querySelector('.shutdown');
            const renameBtn = fileMenu.querySelector('.rename');
            const deleteBtn = fileMenu.querySelector('.delete');
            const downloadBtn = fileMenu.querySelector('.download');
            
            if (openBtn) openBtn.addEventListener('click', () => this.openFile());
            if (shutdownBtn) shutdownBtn.addEventListener('click', () => this.shutdownNotebook());
            if (renameBtn) renameBtn.addEventListener('click', () => this.showRenameDialog());
            if (deleteBtn) deleteBtn.addEventListener('click', () => this.deleteFile());
            if (downloadBtn) downloadBtn.addEventListener('click', () => this.downloadFile());
        }

        // Folder context menu
        const folderMenu = document.getElementById('folderContextMenu');
        if (folderMenu) {
            const newFileBtn = folderMenu.querySelector('.folder-new-file');
            const newFolderBtn = folderMenu.querySelector('.folder-new-folder');
            const renameFolderBtn = folderMenu.querySelector('.folder-rename');
            const deleteFolderBtn = folderMenu.querySelector('.folder-delete');
            
            if (newFileBtn) newFileBtn.addEventListener('click', () => this.createNewFileInFolder());
            if (newFolderBtn) newFolderBtn.addEventListener('click', () => this.createNewFolderInFolder());
            if (renameFolderBtn) renameFolderBtn.addEventListener('click', () => this.showRenameFolderDialog());
            if (deleteFolderBtn) deleteFolderBtn.addEventListener('click', () => this.deleteFolder());
        }
    }
    
    setupPopupDialogs() {
        // New File Dialog
        const newFileBtn = document.getElementById('new-notebook-btn');
        const newFilePopup = document.getElementById('newFilePopup');
        const createFileBtn = document.getElementById('createFileButton');
        const cancelFileBtn = document.getElementById('cancelFileButton');
        
        if (newFileBtn && newFilePopup) {
            newFileBtn.addEventListener('click', () => {
                this.showPopup('newFilePopup');
                document.getElementById('newFileName').focus();
            });
        }
        
        if (createFileBtn) {
            createFileBtn.addEventListener('click', () => {
                const fileName = document.getElementById('newFileName').value.trim();
                if (fileName) {
                    this.createNewNotebook(fileName); //Resolve Backend Issue
                    this.hidePopup('newFilePopup');
                }
            });
        }
        
        if (cancelFileBtn) {
            cancelFileBtn.addEventListener('click', () => {
                this.hidePopup('newFilePopup');
            });
        }

        // New Folder Dialog
        const newFolderBtn = document.getElementById('new-folder-btn');
        const newFolderPopup = document.getElementById('newFolderPopup');
        const createFolderBtn = document.getElementById('createFolderButton');
        const cancelFolderBtn = document.getElementById('cancelFolderButton');
        
        if (newFolderBtn && newFolderPopup) {
            newFolderBtn.addEventListener('click', () => {
                this.showPopup('newFolderPopup');
                document.getElementById('newFolderName').focus();
            });
        }
        
        if (createFolderBtn) {
            createFolderBtn.addEventListener('click', () => {
                const folderName = document.getElementById('newFolderName').value.trim();
                if (folderName) {
                    this.createNewFolder(folderName);
                    this.hidePopup('newFolderPopup');
                }
            });
        }
        
        if (cancelFolderBtn) {
            cancelFolderBtn.addEventListener('click', () => {
                this.hidePopup('newFolderPopup');
            });
        }

        // Upload Dialog
        const uploadBtn = document.getElementById('upload-btn');
        const uploadForm = document.getElementById('uploadFileForm');
        const cancelUploadBtn = document.getElementById('cancelUploadButton');
        
        if (uploadBtn && uploadForm) {
            uploadBtn.addEventListener('click', () => {
                this.showPopup('uploadFileForm');
            });
        }
        
        if (uploadForm) {
            uploadForm.addEventListener('submit', (e) => {
                e.preventDefault();
                this.uploadFile(uploadForm);
            });
        }
        
        if (cancelUploadBtn) {
            cancelUploadBtn.addEventListener('click', () => {
                this.hidePopup('uploadFileForm');
            });
        }

        // Rename Dialog
        const renamePopup = document.getElementById('renameFilePopup');
        const renameBtn = document.getElementById('renameFileButton');
        const cancelRenameBtn = document.getElementById('cancelRenameFileButton');
        
        if (renameBtn) {
            renameBtn.addEventListener('click', () => {
                const newName = document.getElementById('renameFileName').value.trim();
                if (newName && this.currentContextItem) {
                    this.renameFile(this.currentContextItem, newName);
                    this.hidePopup('renameFilePopup');
                }
            });
        }
        
        if (cancelRenameBtn) {
            cancelRenameBtn.addEventListener('click', () => {
                this.hidePopup('renameFilePopup');
            });
        }

        // Close popups when clicking outside
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('popup-dialog')) {
                this.hideAllPopups();
            }
        });

        // Close popups with Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.hideAllPopups();
            }
        });
    }
    
    async loadFileTree() {
        await this.loadFileTreeViaREST();
    }
    

    async loadFileTreeViaREST() {
        try {
            console.log('Loading notebooks via REST API...');
            
            const response = await fetch('/api/notebooks', {
                method: 'GET',
                credentials: 'include',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                console.log('REST API response:', data);
                
                if (data.notebooks && Array.isArray(data.notebooks)) {
                    this.fileTree = this.convertNotebooksToTree(data.notebooks);
                    this.renderFileTree();
                    console.log(`Loaded ${data.count} notebooks for user: ${data.user}`);
                } else {
                    console.warn('Invalid response format from /api/notebooks');
                    this.fileTree = this.createEmptyFileTree();
                    this.renderFileTree();
                }
            } else {
                console.error('Failed to load notebooks:', response.status, response.statusText);
                this.fileTree = this.createEmptyFileTree();
                this.renderFileTree();
            }
        } catch (error) {
            console.error('Failed to load via REST:', error);
            this.fileTree = this.createEmptyFileTree();
            this.renderFileTree();
        }
    }
    
    convertNotebooksToTree(notebooks) {
        console.log('Converting notebooks to tree using shortpath:', notebooks);
        
        const tree = {
            name: 'root',
            type: 'directory',
            path: '',
            contents: []
        };
        
        if (!notebooks || !Array.isArray(notebooks)) {
            console.warn('Invalid notebooks data:', notebooks);
            return tree;
        }
        
        // Group notebooks by directory using shortpath
        const pathMap = new Map();
        
        notebooks.forEach((notebook) => {
            // Use shortpath to determine directory structure
            const shortpath = notebook.shortpath || notebook.name || 'unknown.jl';
            
            // Split on both forward and back slashes to handle Windows paths
            const parts = shortpath.split(/[\/\\]/);
            const filename = parts.pop() || 'unknown.jl';
            const dirPath = parts.length > 0 ? parts.join('/') : '';
            
            // Group by directory
            if (!pathMap.has(dirPath)) {
                pathMap.set(dirPath, []);
            }
            
            pathMap.get(dirPath).push({
                name: filename,
                type: 'file',
                shortpath: shortpath,
                notebook_id: notebook.notebook_id,
                process_status: notebook.process_status || 'not_running',
                in_temp_dir: notebook.in_temp_dir || false,
                is_running: notebook.is_running || false,
                size: notebook.size || 0,
                modified: notebook.modified || '',
                // Store full notebook data for operations
                _notebook_data: notebook
            });
        });
        
        console.log('Path map:', pathMap);
        
        // Build tree structure using relative paths
        pathMap.forEach((files, dirPath) => {
            if (dirPath === '' || dirPath === '.') {
                // Files in root directory
                tree.contents.push(...files);
            } else {
                // Files in subdirectories
                const dirParts = dirPath.split('/').filter(part => part.length > 0);
                let currentDir = tree;
                
                // Create directory structure
                dirParts.forEach((part, index) => {
                    let subDir = currentDir.contents.find(item => 
                        item.type === 'directory' && item.name === part
                    );
                    
                    if (!subDir) {
                        subDir = {
                            name: part,
                            type: 'directory',
                            path: dirParts.slice(0, index + 1).join('/'),
                            shortpath: dirParts.slice(0, index + 1).join('/'),
                            contents: []
                        };
                        currentDir.contents.push(subDir);
                    }
                    
                    currentDir = subDir;
                });
                
                // Add files to the deepest directory
                currentDir.contents.push(...files);
            }
        });
        
        // Sort contents: directories first, then files, both alphabetically
        const sortContents = (contents) => {
            contents.sort((a, b) => {
                if (a.type !== b.type) {
                    return a.type === 'directory' ? -1 : 1;
                }
                return a.name.localeCompare(b.name);
            });
            
            // Recursively sort subdirectories
            contents.forEach(item => {
                if (item.type === 'directory' && item.contents) {
                    sortContents(item.contents);
                }
            });
        };
        
        sortContents(tree.contents);
        
        console.log('Built tree structure:', tree);
        return tree;
    }
    
    createMockFileTree() {
        return {
            name: 'root',
            type: 'directory',
            path: '',
            contents: [
                {
                    name: 'Welcome to Pluto.jl',
                    type: 'file',
                    path: 'Welcome to Pluto.jl',
                    notebook_id: 'welcome'
                },
                {
                    name: 'example.jl',
                    type: 'file',
                    path: 'example.jl',
                    notebook_id: 'example'
                }
            ]
        };
    }
    
    renderFileTree() {
        const container = document.getElementById('directoryTree');
        if (!container) {
            console.warn('Directory tree container not found');
            return;
        }
        
        container.innerHTML = '';
        
        if (this.fileTree && this.fileTree.contents) {
            this.fileTree.contents.forEach(item => {
                this.createTreeItem(item, container);
            });
        } else {
            container.innerHTML = '<li class="empty-message">No notebooks found</li>';
        }
    }
    
    createTreeItem(item, parentElement) {
        const listItem = document.createElement('li');
        listItem.className = item.type === 'directory' ? 'folder' : 'file';
        listItem.dataset.shortpath = item.shortpath;
        
        if (item.notebook_id) {
            listItem.dataset.notebookId = item.notebook_id;
        }
        
        const icon = document.createElement('i');
        icon.className = item.type === 'directory' ? 'fas fa-folder' : 'fa-solid fa-file';
        
        listItem.appendChild(icon);
        listItem.appendChild(document.createTextNode(' ' + item.name));
        
        // Add status indicators for files
        if (item.type === 'file') {
            // Running status indicator
            if (item.is_running) {
                const statusIcon = document.createElement('span');
                statusIcon.classList.add('status-indicator', 'status-running');
                statusIcon.title = 'Notebook is running';
                statusIcon.textContent = ' ●';
                statusIcon.style.color = '#4CAF50';
                listItem.appendChild(statusIcon);
            } else {
                const statusIcon = document.createElement('span');
                statusIcon.classList.add('status-indicator', 'status-not-running');
                statusIcon.title = 'Notebook is not running';
                statusIcon.textContent = ' ○';
                statusIcon.style.color = '#999';
                listItem.appendChild(statusIcon);
            }
            
            // File size indicator (optional)
            if (item.size > 0) {
                const sizeIcon = document.createElement('span');
                sizeIcon.classList.add('size-indicator');
                sizeIcon.title = `Size: ${this.formatFileSize(item.size)}`;
                sizeIcon.textContent = ` (${this.formatFileSize(item.size)})`;
                sizeIcon.style.color = '#666';
                sizeIcon.style.fontSize = '0.8em';
                listItem.appendChild(sizeIcon);
            }
        }
        
        parentElement.appendChild(listItem);
        
        // Handle directory expansion
        if (item.type === 'directory' && item.contents && item.contents.length > 0) {
            const subList = document.createElement('ul');
            subList.classList.add('hidden');
            parentElement.appendChild(subList);
            
            // Add folder icon toggle
            listItem.addEventListener('click', (e) => {
                e.stopPropagation();
                subList.classList.toggle('hidden');
                
                // Change folder icon
                if (subList.classList.contains('hidden')) {
                    icon.className = 'fas fa-folder';
                } else {
                    icon.className = 'fas fa-folder-open';
                }
                
                // Lazy load directory contents
                if (!subList.classList.contains('hidden') && subList.children.length === 0) {
                    item.contents.forEach(subItem => {
                        this.createTreeItem(subItem, subList);
                    });
                }
            });

            // Add folder context menu
            listItem.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                this.showContextMenu(e, 'folderContextMenu', item);
            });
        }
        
        // Handle file interactions
        if (item.type === 'file') {
            listItem.addEventListener('dblclick', () => this.openFile(item));
            listItem.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                this.showContextMenu(e, 'fileContextMenu', item);
            });
        }
    }
    
    showContextMenu(event, menuId, item) {
        this.hideAllContextMenus();
        
        const menu = document.getElementById(menuId);
        if (!menu) return;
        
        this.currentContextItem = item;
        
        menu.style.display = 'block';
        menu.style.left = `${event.clientX}px`;
        menu.style.top = `${event.clientY}px`;
    }
    
    hideAllContextMenus() {
        document.querySelectorAll('.context-menu').forEach(menu => {
            menu.style.display = 'none';
        });
        this.currentContextItem = null;
    }
    
    showPopup(popupId) {
        const popup = document.getElementById(popupId);
        if (popup) popup.classList.add('show');
    }
    
    hidePopup(popupId) {
        const popup = document.getElementById(popupId);
        if (popup) popup.classList.remove('show');
    }

    hideAllPopups() {
        document.querySelectorAll('.popup-dialog').forEach(popup => {
            popup.classList.remove('show');
        });
    }
    
    async openFile(item = this.currentContextItem) {
        if (!item || item.type !== 'file') return;
        
        const url = `/edit?id=${item.notebook_id}`;
        console.log('Opening notebook:', url);
        window.location.href = url;
    }
    
    async createNewFile() {
        window.location.href = '/new';
    }

    async createNewFileInFolder() {
        // Set the current folder context for new file creation
        this.showPopup('newFilePopup');
        this.hideAllContextMenus();
    }

    async createNewNotebook(fileName) {
        if (!fileName.endsWith('.jl')) {
            fileName += '.jl';
        }
        
        try {
            // Create new notebook - you might need to adjust this URL
            window.location.href = `/new?name=${encodeURIComponent(fileName)}`;
        } catch (error) {
            console.error('Failed to create notebook:', error);
            alert('Failed to create notebook: ' + error.message);
        }
    }

    showRenameDialog() {
        if (!this.currentContextItem) return;
        
        const input = document.getElementById('renameFileName');
        if (input) {
            input.value = this.currentContextItem.name;
        }
        this.showPopup('renameFilePopup');
        this.hideAllContextMenus();
    }

    async renameFile(item, newName) {
        console.log('Renaming file:', item.name, 'to:', newName);
        // TODO: Implement file rename API
        alert('File rename not implemented yet');
    }
    
    // Implement delete file in backend
    async deleteFile(item = this.currentContextItem) {
        if (!item || item.type !== 'file') return;
        
        if (!confirm(`Delete ${item.name}?`)) return;
        
        try {
            if (this.client) {
                await this.client.send("shutdown_notebook", 
                    { keep_in_session: false }, 
                    { notebook_id: item.notebook_id }
                );
            } else {
                const response = await fetch(`/shutdown?id=${item.notebook_id}`, {
                    method: 'POST',
                    credentials: 'include'
                });
                if (!response.ok) throw new Error('Delete failed');
            }
            
            await this.loadFileTree();
            this.hideAllContextMenus();
        } catch (error) {
            console.error('Delete failed:', error);
            alert('Delete failed: ' + error.message);
        }
    }

    async shutdownNotebook() {
        if (!this.currentContextItem || this.currentContextItem.notebook_id == null) {
            alert('This notebook is not currently running');
            return;
        }
        
        if (!confirm(`Shutdown notebook "${this.currentContextItem.name}"?`)) return;
        
        try {
            const response = await fetch(`/shutdown?id=${this.currentContextItem.notebook_id}`, {
                method: 'POST',
                credentials: 'include'
            });
            
            if (!response.ok) {
                throw new Error(`Failed to shutdown: ${response.status}`);
            }
            
            await this.loadFileTree();
            this.hideAllContextMenus();
            alert('Notebook shutdown successfully');
        } catch (error) {
            console.error('Failed to shutdown notebook:', error);
            alert('Failed to shutdown notebook: ' + error.message);
        }
    }
    
    async downloadFile(item = this.currentContextItem) {
        if (!item || item.type !== 'file') return;

        // Alert for now
        if (item.notebook_id == null) {
            alert('File must be running to be downloaded');
            return;
        }
        
        try {
            const response = await fetch(`/notebookfile?id=${item.notebook_id}`, {
                credentials: 'include'
            });
            
            if (response.ok) {
                const blob = await response.blob();
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = item.name;
                a.click();
                URL.revokeObjectURL(url);
                this.hideAllContextMenus();
            }
        } catch (error) {
            console.error('Download failed:', error);
            alert('Download failed');
        }
    }

    async uploadFile(form) {
        try {
            // Get the file input element
            const fileInput = form.querySelector('input[type="file"]');
            if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
                throw new Error('No file selected');
            }

            // Get the selected file
            const file = fileInput.files[0];
            
            // Validate file type
            if (!file.name.endsWith('.jl')) {
                throw new Error('Please select a valid Pluto notebook (.jl) file');
            }
            
            // Read file content as text
            const fileContent = await this.readFileAsText(file);
            
            // Validate it's a Pluto notebook
            if (!fileContent.startsWith('### A Pluto.jl notebook ###')) {
                throw new Error('This file does not appear to be a valid Pluto notebook');
            }
            
            console.log('File name:', file.name);
            console.log('File size:', file.size, 'bytes');
            console.log('File content preview:', fileContent.substring(0, 200) + '...');
            
            // Option 1: Send as FormData (original approach)
            // const formData = new FormData();
            // formData.append('notebookfile', file);
        
            const response = await fetch('/notebookupload?name=' + encodeURIComponent(file.name), {
                method: 'POST',
                credentials: 'include',
                body: fileContent
            });
            
            if (response.ok) {
                await this.loadFileTree();
                this.hidePopup('uploadFileForm');
                form.reset();
                alert('File uploaded successfully');
            } else {
                throw new Error(`Upload failed: ${response.status}`);
            }
        } catch (error) {
            console.error('Upload failed:', error);
            alert('Upload failed: ' + error.message);
        }
    }

    // Helper method to read file content as text
    readFileAsText(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            
            reader.onload = (event) => {
                resolve(event.target.result);
            };
            
            reader.onerror = (event) => {
                reject(new Error('Failed to read file: ' + event.target.error));
            };
            
            reader.readAsText(file, 'utf-8');
        });
    }
    
    filterFiles(query) {
        const items = document.querySelectorAll('#directoryTree li');
        const lowerQuery = query.toLowerCase();
        
        items.forEach(item => {
            const text = item.textContent.toLowerCase();
            item.style.display = !query || text.includes(lowerQuery) ? '' : 'none';
        });
    }

    // Folder operations
    async createNewFolder(folderName) {
        console.log('Creating folder:', folderName);
        // TODO: Implement folder creation API
        alert('Folder creation not implemented yet');
    }

    async createNewFolderInFolder() {
        this.showPopup('newFolderPopup');
        this.hideAllContextMenus();
    }

    async deleteFolder() {
        if (!this.currentContextItem) return;
        
        if (!confirm(`Delete folder "${this.currentContextItem.name}" and all its contents?`)) return;
        
        console.log('Deleting folder:', this.currentContextItem.name);
        // TODO: Implement folder deletion API
        alert('Folder deletion not implemented yet');
        this.hideAllContextMenus();
    }

    // Debug methods
    logDataStructure() {
        console.log('=== FILE BROWSER DEBUG ===');
        console.log('Client:', this.client);
        console.log('window.pluto_client:', window.pluto_client);
        console.log('File tree:', this.fileTree);
        console.log('========================');
    }
}

// Initialize
let plutoFileBrowser;

const initializeFileBrowser = () => {
    if (!plutoFileBrowser) {
        plutoFileBrowser = new PlutoFileBrowser();
        window.plutoFileBrowser = plutoFileBrowser;
        window.debugFileBrowser = () => plutoFileBrowser.logDataStructure();
    }
};

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeFileBrowser);
} else {
    initializeFileBrowser();
}