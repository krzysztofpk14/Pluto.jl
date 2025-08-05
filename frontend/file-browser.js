class PlutoFileBrowser {
    constructor() {
        this.currentUser = null;
        this.fileTree = null;
        this.isInitialized = false;
        this.client = null;
        
        this.init();
    }
    
    init() {
        // Wait for DOM to be ready and Editor to establish connection
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.waitForEditorAndInitialize());
        } else {
            this.waitForEditorAndInitialize();
        }
    }
    
    async waitForEditorAndInitialize() {
        // Simple approach: just wait for window.pluto_client
        let attempts = 0;
        const maxAttempts = 100; // 10 seconds max wait
        
        const checkForClient = () => {
            attempts++;
            
            if (window.pluto_client && typeof window.pluto_client.send === 'function') {
                this.client = window.pluto_client;
                console.log('Found Pluto client from window.pluto_client');
                this.initialize();
                return;
            }
            
            if (attempts >= maxAttempts) {
                console.warn('Pluto client not found after waiting, proceeding with REST API only');
                this.initialize();
                return;
            }
            
            setTimeout(checkForClient, 100);
        };
        
        checkForClient();
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
    
    async initialize() {
        try {
            await this.getCurrentUser();
            this.setupEventListeners();
            await this.loadFileTree();
            
            this.isInitialized = true;
            console.log('Pluto File Browser initialized');
            console.log('Using client:', !!this.client);
        } catch (error) {
            console.error('Failed to initialize file browser:', error);
            this.setupEventListeners();
            this.loadFileTreeViaREST();
        }
    }
    
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
            newNotebookBtn.addEventListener('click', () => this.createNewFile());
        }
    }
    
    setupContextMenus() {
        // File context menu
        const fileMenu = document.getElementById('fileContextMenu');
        if (fileMenu) {
            const openBtn = fileMenu.querySelector('.open');
            const deleteBtn = fileMenu.querySelector('.delete');
            const downloadBtn = fileMenu.querySelector('.download');
            
            if (openBtn) openBtn.addEventListener('click', () => this.openFile());
            if (deleteBtn) deleteBtn.addEventListener('click', () => this.deleteFile());
            if (downloadBtn) downloadBtn.addEventListener('click', () => this.downloadFile());
        }
    }
    
    setupPopupDialogs() {
        // Minimal popup setup - add more as needed
    }
    
    async loadFileTree() {
        if (this.client && typeof this.client.send === 'function') {
            await this.loadFileTreeViaClient();
        } else {
            await this.loadFileTreeViaREST();
        }
    }
    
   async loadFileTreeViaClient() {
        try {
            console.log('Loading notebooks via client...');
            
            // The correct message type appears to be one that returns 'notebook_list'
            // Let's try a few possibilities
            const possibleMessageTypes = [
                'get_all_notebooks',
                'notebook_list', 
                'list_notebooks',
                'get_notebooks'
            ];
            
            let response = null;
            let usedMessageType = null;
            
            for (const messageType of possibleMessageTypes) {
                try {
                    console.log(`Trying message type: ${messageType}`);
                    response = await this.client.send(messageType, {}, {});
                    
                    // Check if we got the expected response structure
                    if (response && response.type === 'notebook_list' && response.message && response.message.notebooks) {
                        usedMessageType = messageType;
                        console.log(`Success with message type: ${messageType}`, response);
                        break;
                    }
                } catch (error) {
                    console.log(`Failed with message type: ${messageType}:`, error.message);
                }
            }
            
            if (!response || response.type !== 'notebook_list') {
                console.warn('No valid notebook list response found, falling back to REST API');
                await this.loadFileTreeViaREST();
                return;
            }
            
            // Extract notebooks from the response
            const notebooks = response.message.notebooks;
            console.log(`Loaded ${notebooks.length} notebooks via client (${usedMessageType}):`, notebooks);
            
            // Convert to file tree format
            this.fileTree = this.convertNotebooksToTree(notebooks);
            this.renderFileTree();
            
        } catch (error) {
            console.error('Failed to load file tree via client:', error);
            await this.loadFileTreeViaREST();
        }
    }
    
    async loadFileTreeViaREST() {
        try {
            console.log('Loading notebooks via REST API...');
            
            const response = await fetch('/notebooklist', {
                method: 'GET',
                credentials: 'include'
            });
            
            if (response.ok) {
                const text = await response.text();
                console.log('REST response:', text);
                
                // Try to parse as JSON
                try {
                    const notebooks = JSON.parse(text);
                    this.fileTree = this.convertNotebooksToTree(notebooks);
                } catch (e) {
                    // If not JSON, use mock data
                    this.fileTree = this.createMockFileTree();
                }
            } else {
                this.fileTree = this.createMockFileTree();
            }
            
            this.renderFileTree();
        } catch (error) {
            console.error('Failed to load via REST:', error);
            this.fileTree = this.createMockFileTree();
            this.renderFileTree();
        }
    }
    
    convertNotebooksToTree(notebooks) {
        console.log('Converting Pluto notebooks to tree:', notebooks);
        
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
        
        // Group notebooks by directory
        const pathMap = new Map();
        
        notebooks.forEach((notebook) => {
            // Extract directory path from full path
            const fullPath = notebook.path || notebook.shortpath || `notebook-${notebook.notebook_id}`;
            const parts = fullPath.split(/[\/\\]/);
            const filename = parts.pop() || 'unknown.jl';
            const dirPath = parts.join('/');
            
            // Group by directory
            if (!pathMap.has(dirPath)) {
                pathMap.set(dirPath, []);
            }
            
            pathMap.get(dirPath).push({
                name: notebook.shortpath || filename,
                type: 'file',
                path: notebook.path,
                notebook_id: notebook.notebook_id,
                process_status: notebook.process_status,
                in_temp_dir: notebook.in_temp_dir,
                shortpath: notebook.shortpath
            });
        });
        
        // Build tree structure
        pathMap.forEach((files, dirPath) => {
            if (dirPath === '' || dirPath === '.') {
                // Files in root directory
                tree.contents.push(...files);
            } else {
                // Files in subdirectories
                const dirParts = dirPath.split(/[\/\\]/).filter(part => part.length > 0);
                let currentDir = tree;
                
                // Create directory structure
                dirParts.forEach(part => {
                    let subDir = currentDir.contents.find(item => 
                        item.type === 'directory' && item.name === part
                    );
                    
                    if (!subDir) {
                        subDir = {
                            name: part,
                            type: 'directory',
                            path: dirPath,
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
        listItem.dataset.path = item.path;
        listItem.dataset.notebookId = item.notebook_id;
        
        const icon = document.createElement('i');
        icon.className = item.type === 'directory' ? 'fas fa-folder' : 'fas fa-file-code';
        
        listItem.appendChild(icon);
        listItem.appendChild(document.createTextNode(' ' + item.name));
        
        // Add process status indicator for files
        if (item.type === 'file' && item.process_status) {
            const statusIcon = document.createElement('span');
            statusIcon.classList.add('status-indicator');
            statusIcon.classList.add(`status-${item.process_status}`);
            statusIcon.title = `Status: ${item.process_status}`;
            statusIcon.textContent = ' ●';
            statusIcon.style.color = item.process_status === 'ready' ? '#4CAF50' : '#FF9800';
            listItem.appendChild(statusIcon);
        }
        
        // Add temp directory indicator
        if (item.type === 'file' && item.in_temp_dir) {
            const tempIcon = document.createElement('span');
            tempIcon.classList.add('temp-indicator');
            tempIcon.title = 'Temporary notebook';
            tempIcon.textContent = ' (temp)';
            tempIcon.style.color = '#999';
            tempIcon.style.fontSize = '0.8em';
            listItem.appendChild(tempIcon);
        }
        
        parentElement.appendChild(listItem);
        
        // Handle directory expansion
        if (item.type === 'directory' && item.contents && item.contents.length > 0) {
            const subList = document.createElement('ul');
            subList.classList.add('hidden');
            parentElement.appendChild(subList);
            
            listItem.addEventListener('click', (e) => {
                e.stopPropagation();
                subList.classList.toggle('hidden');
                
                if (!subList.classList.contains('hidden') && subList.children.length === 0) {
                    item.contents.forEach(subItem => {
                        this.createTreeItem(subItem, subList);
                    });
                }
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
    
    async openFile(item = this.currentContextItem) {
        if (!item || item.type !== 'file') return;
        
        const url = `/edit?id=${item.notebook_id}`;
        console.log('Opening notebook:', url);
        window.location.href = url;
    }
    
    async createNewFile() {
        window.location.href = '/new';
    }
    
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
    
    async downloadFile(item = this.currentContextItem) {
        if (!item || item.type !== 'file') return;
        
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
    
    filterFiles(query) {
        const items = document.querySelectorAll('#directoryTree li');
        const lowerQuery = query.toLowerCase();
        
        items.forEach(item => {
            const text = item.textContent.toLowerCase();
            item.style.display = !query || text.includes(lowerQuery) ? '' : 'none';
        });
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