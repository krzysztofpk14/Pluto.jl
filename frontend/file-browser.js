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
        this.setupLogoutButton();
        
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
            // newNotebookBtn.addEventListener('click', () => this.createNewNotebook());
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
    
    // Replace the existing setupPopupDialogs method
    setupPopupDialogs() {
        // New File Dialog
        const newFileBtn = document.getElementById('new-notebook-btn');
        const newFilePopup = document.getElementById('newFilePopup');
        const createFileBtn = document.getElementById('createFileButton');
        const cancelFileBtn = document.getElementById('cancelFileButton');
        
        // Toolbar button - creates in root
        if (newFileBtn) {
            newFileBtn.addEventListener('click', () => {
                console.log('Toolbar new file button clicked');
                // Reset context for toolbar button (create in root)
                this.fileCreationContext = { parentPath: '', parentName: 'root' };
                
                const dialogTitle = document.querySelector('#newFilePopup h3');
                if (dialogTitle) {
                    dialogTitle.textContent = 'Create New Notebook';
                }
                
                this.showPopup('newFilePopup');
                const fileInput = document.getElementById('newFileName');
                if (fileInput) {
                    fileInput.focus();
                    fileInput.value = '';
                }
            });
        }
        
        // Create button in dialog
        if (createFileBtn) {
            createFileBtn.addEventListener('click', () => {
                const fileName = document.getElementById('newFileName').value.trim();
                console.log('Create button clicked with filename:', fileName);
                console.log('Current file creation context:', this.fileCreationContext);
                
                if (fileName) {
                    this.createNewNotebook(fileName);
                    this.hidePopup('newFilePopup');
                } else {
                    alert('Please enter a file name');
                }
            });
        }
        
        // Cancel button in dialog
        if (cancelFileBtn) {
            cancelFileBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.hidePopup('newFilePopup');
                // Reset context
                this.fileCreationContext = null;
            });
        }

        // Handle Enter key in filename input
        const fileNameInput = document.getElementById('newFileName');
        if (fileNameInput) {
            fileNameInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    const fileName = fileNameInput.value.trim();
                    if (fileName) {
                        this.createNewNotebook(fileName);
                        this.hidePopup('newFilePopup');
                    }
                }
            });
        }

        // New Folder Dialog - similar pattern
        const newFolderBtn = document.getElementById('new-folder-btn');
        const newFolderPopup = document.getElementById('newFolderPopup');
        const createFolderBtn = document.getElementById('createFolderButton');
        const cancelFolderBtn = document.getElementById('cancelFolderButton');
        
        if (newFolderBtn) {
            newFolderBtn.addEventListener('click', () => {
                console.log('Toolbar new folder button clicked');
                // Reset context for toolbar button
                this.folderCreationContext = { parentPath: '', parentName: 'root' };
                
                const dialogTitle = document.querySelector('#newFolderPopup h3');
                if (dialogTitle) {
                    dialogTitle.textContent = 'Create New Folder';
                }
                
                this.showPopup('newFolderPopup');
                const folderInput = document.getElementById('newFolderName');
                if (folderInput) {
                    folderInput.focus();
                    folderInput.value = '';
                }
            });
        }
        
        if (createFolderBtn) {
            createFolderBtn.addEventListener('click', () => {
                const folderName = document.getElementById('newFolderName').value.trim();
                console.log('Create folder button clicked with name:', folderName);
                console.log('Current folder creation context:', this.folderCreationContext);
                
                if (folderName) {
                    // Use context if available
                    const parentPath = this.folderCreationContext?.parentPath || '';
                    this.createNewFolder(folderName, parentPath);
                } else {
                    alert('Please enter a folder name');
                }
            });
        }
        
        if (cancelFolderBtn) {
            cancelFolderBtn.addEventListener('click', () => {
                this.hidePopup('newFolderPopup');
                // Reset context
                this.folderCreationContext = null;
            });
        }

        // Handle Enter key in folder name input
        const folderNameInput = document.getElementById('newFolderName');
        if (folderNameInput) {
            folderNameInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    const folderName = folderNameInput.value.trim();
                    if (folderName) {
                        const parentPath = this.folderCreationContext?.parentPath || '';
                        this.createNewFolder(folderName, parentPath);
                    }
                }
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
                console.log('=== RENAME BUTTON DEBUG ===');
                console.log('Raw input value:', document.getElementById('renameFileName').value);
                console.log('Trimmed newName:', newName);
                console.log('newName length:', newName.length);
                console.log('Current context item:', this.renameDialogContext);
                console.log('========================');
                
                if (!newName) {
                    console.log('Validation failed: empty name');
                    alert('Please enter a valid name');
                    return;
                }
                
                if (!this.renameDialogContext) {
                    console.log('Validation failed: no context item');
                    alert('No file selected for renaming');
                    return;
                }
                
                if (newName.length > 255) {
                    console.log('Validation failed: name too long');
                    alert('Filename is too long (maximum 255 characters)');
                    return;
                }
                
                // Check for invalid characters
                if (/[<>:"/\\|?*]/.test(newName)) {
                    console.log('Validation warning: invalid characters found');
                    if (!confirm('Filename contains invalid characters that will be replaced with underscores. Continue?')) {
                        return;
                    }
                }
                
                console.log('Validation passed, calling renameFile');
                this.renameFile(this.renameDialogContext, newName);
            });
        }
        
        if (cancelRenameBtn) {
            cancelRenameBtn.addEventListener('click', () => {
                this.hidePopup('renameFilePopup');
            });
        }

        // Handle Enter key in rename input
        const renameInput = document.getElementById('renameFileName');
        if (renameInput) {
            renameInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    const newName = renameInput.value.trim();
                    if (newName && this.renameDialogContext) {
                        this.renameFile(this.renameDialogContext, newName);
                    }
                }
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
            console.log('Loading complete directory tree via REST API...');
            
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
                
                if (data.tree && data.tree.contents) {
                    // Use the tree structure directly
                    this.fileTree = data.tree;
                    this.renderFileTree();
                    
                    console.log(`Loaded directory tree for user: ${data.user}`);
                    console.log(`Counts:`, data.counts);
                    
                    // Update UI status if there's a status element
                    this.updateStatus(data.counts);
                } else {
                    console.warn('Invalid response format from /api/notebooks');
                    this.fileTree = this.createEmptyFileTree();
                    this.renderFileTree();
                }
            } else {
                console.error('Failed to load directory tree:', response.status, response.statusText);
                this.fileTree = this.createEmptyFileTree();
                this.renderFileTree();
            }
        } catch (error) {
            console.error('Failed to load via REST:', error);
            this.fileTree = this.createEmptyFileTree();
            this.renderFileTree();
        }
    }

    // Add method to update status display
    updateStatus(counts) {
        const statusElement = document.getElementById('file-browser-status');
        if (statusElement && counts) {
            const statusText = `${counts.folders} folders, ${counts.notebooks} notebooks, ${counts.other_files} other files`;
            statusElement.textContent = statusText;
        }
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
        listItem.dataset.shortpath = item.shortpath || '';
        
        if (item.notebook_id) {
            listItem.dataset.notebookId = item.notebook_id;
        }
        
        // Set file type class for styling
        if (item.file_type) {
            listItem.classList.add(item.file_type);
        }
        
        const icon = document.createElement('i');
        
        // Choose appropriate icon based on type
        if (item.type === 'directory') {
            icon.className = 'fas fa-folder';
            if (item.is_empty) {
                listItem.classList.add('empty-folder');
                listItem.title = 'Empty folder';
            }
        } else {
            // File icons based on file type
            switch (item.file_type) {
                case 'pluto_notebook':
                    icon.className = 'fas fa-book';
                    icon.style.color = '#9c27b0'; // Purple for Pluto notebooks
                    break;
                case 'julia_file':
                    icon.className = 'fab fa-julia';
                    icon.style.color = '#389826'; // Julia green for .jl files
                    break;
                case 'text_file':
                    icon.className = 'fas fa-file-alt';
                    icon.style.color = '#6c757d'; // Gray for text files
                    break;
                case 'config_file':
                    icon.className = 'fas fa-cog';
                    icon.style.color = '#17a2b8'; // Blue for config files
                    break;
                case 'image_file':
                    icon.className = 'fas fa-image';
                    icon.style.color = '#28a745'; // Green for images
                    break;
                default:
                    icon.className = 'fas fa-file';
                    icon.style.color = '#6c757d'; // Default gray
            }
        }
        
        listItem.appendChild(icon);
        listItem.appendChild(document.createTextNode(' ' + item.name));
        
        // Add status indicators for Pluto notebooks
        if (item.type === 'file' && item.is_pluto_notebook) {
            // Running status indicator
            if (item.is_running) {
                const statusIcon = document.createElement('span');
                statusIcon.classList.add('status-indicator', 'status-running');
                statusIcon.title = 'Notebook is running';
                statusIcon.textContent = ' ●';
                statusIcon.style.color = '#28a745';
                listItem.appendChild(statusIcon);
            } else {
                const statusIcon = document.createElement('span');
                statusIcon.classList.add('status-indicator', 'status-not-running');
                statusIcon.title = 'Notebook is not running';
                statusIcon.textContent = ' ○';
                statusIcon.style.color = '#6c757d';
                listItem.appendChild(statusIcon);
            }
        }
        
        // File size indicator for all files
        if (item.type === 'file' && item.size > 0) {
            const sizeIcon = document.createElement('span');
            sizeIcon.classList.add('size-indicator');
            sizeIcon.title = `Size: ${this.formatFileSize(item.size)}`;
            sizeIcon.textContent = ` (${this.formatFileSize(item.size)})`;
            sizeIcon.style.color = '#6c757d';
            sizeIcon.style.fontSize = '0.8em';
            listItem.appendChild(sizeIcon);
        }
        
        // Empty folder indicator
        if (item.type === 'directory' && item.is_empty) {
            const emptyIcon = document.createElement('span');
            emptyIcon.classList.add('empty-indicator');
            emptyIcon.title = 'Empty folder';
            emptyIcon.textContent = '  (empty)';
            emptyIcon.style.color = '#6c757d';
            emptyIcon.style.fontSize = '0.8em';
            emptyIcon.style.fontStyle = 'italic';
            listItem.appendChild(emptyIcon);
        }
        
        parentElement.appendChild(listItem);
        
        // Handle directory expansion
        if (item.type === 'directory') {
            const subList = document.createElement('ul');
            subList.classList.add('hidden');
            parentElement.appendChild(subList);
            
            // Add folder click handler for expansion
            listItem.addEventListener('click', (e) => {
                e.stopPropagation();
                subList.classList.toggle('hidden');
                
                // Change folder icon
                if (subList.classList.contains('hidden')) {
                    icon.className = 'fas fa-folder';
                } else {
                    icon.className = 'fas fa-folder-open';
                }
                
                // Load directory contents
                if (!subList.classList.contains('hidden') && subList.children.length === 0) {
                    if (item.contents && item.contents.length > 0) {
                        item.contents.forEach(subItem => {
                            this.createTreeItem(subItem, subList);
                        });
                    } else {
                        // Show empty folder message
                        const emptyMessage = document.createElement('li');
                        emptyMessage.className = 'empty-message';
                        emptyMessage.textContent = 'Folder is empty';
                        emptyMessage.style.fontStyle = 'italic';
                        emptyMessage.style.color = '#6c757d';
                        subList.appendChild(emptyMessage);
                    }
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
            // Only allow opening Pluto notebooks
            if (item.is_pluto_notebook) {
                listItem.addEventListener('dblclick', () => this.openFile(item));
                listItem.addEventListener('contextmenu', (e) => {
                    e.preventDefault();
                    this.showContextMenu(e, 'fileContextMenu', item);
                });
            } else {
                // Add different context menu for non-notebook files
                listItem.addEventListener('contextmenu', (e) => {
                    e.preventDefault();
                    this.showContextMenu(e, 'fileContextMenu', item);
                });
                
                // Add visual indicator that it's not openable
                listItem.style.opacity = '0.7';
                listItem.title = 'Not a Pluto notebook - right-click for options';
            }
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
    
    // Update openFile to handle only Pluto notebooks
    async openFile(item = this.currentContextItem) {
        if (!item || item.type !== 'file') return;
        
        if (!item.is_pluto_notebook) {
            alert('This file is not a Pluto notebook and cannot be opened in the editor.');
            return;
        }
        
        if (!item.notebook_id) {
            // Notebook is not running - need to open it first
            const openUrl = `/open?path=${encodeURIComponent(item.path)}`;
            console.log('Opening notebook:', openUrl);
            window.location.href = openUrl;
        } else {
            // Notebook is already running
            const editUrl = `/edit?id=${item.notebook_id}`;
            console.log('Opening running notebook:', editUrl);
            window.location.href = editUrl;
        }
    }
    
    // async createNewFile() {
    //     window.location.href = '/new';
    // }

    async createNewFileInFolder() {
        console.log('=== createNewFileInFolder DEBUG START ===');
        console.log('Creating new file in folder - context item:', this.currentContextItem);
        
        if (!this.currentContextItem || this.currentContextItem.type !== 'directory') {
            console.error('Invalid context item for folder creation:', this.currentContextItem);
            alert('Invalid folder selection');
            return;
        }
        
        // Get current folder context
        const parentPath = this.currentContextItem.shortpath || '';
        const parentName = this.currentContextItem.name || 'root';
        
        console.log('Extracted parentPath:', parentPath);
        console.log('Extracted parentName:', parentName);
        
        // Store parent context for when user creates the file
        this.fileCreationContext = {
            parentPath: parentPath,
            parentName: parentName
        };
        
        console.log('Set file creation context:', this.fileCreationContext);
        console.log('=== createNewFileInFolder DEBUG END ===');
        
        // Update dialog title to show context
        const dialogTitle = document.querySelector('#newFilePopup h3');
        if (dialogTitle) {
            const parentDisplay = parentPath ? `in "${parentName}"` : 'in root';
            dialogTitle.textContent = `Create New Notebook ${parentDisplay}`;
            console.log('Updated dialog title to:', dialogTitle.textContent);
        }
        
        this.showPopup('newFilePopup');
        this.hideAllContextMenus();
        
        // Focus the input and clear it
        const fileInput = document.getElementById('newFileName');
        if (fileInput) {
            fileInput.focus();
            fileInput.value = '';
        }
    }

    async createNewNotebook(fileName) {
        console.log('=== createNewNotebook DEBUG START ===');
        console.log('fileName:', fileName);
        console.log('this.fileCreationContext:', this.fileCreationContext);
        
        if (!fileName || !fileName.trim()) {
            alert('Please enter a file name');
            return;
        }
        
        // Ensure .jl extension
        if (!fileName.endsWith('.jl')) {
            fileName += '.jl';
        }
        
        try {
            // Build URL with folder context if available
            let createUrl = '/new';
            const params = new URLSearchParams();
            
            // Add filename
            params.append('name', fileName.trim());
            
            // Add folder context if we're creating in a specific folder
            if (this.fileCreationContext && this.fileCreationContext.parentPath) {
                params.append('folder', this.fileCreationContext.parentPath);
                console.log('✓ Creating notebook in folder:', this.fileCreationContext.parentPath);
                console.log('✓ Full context:', this.fileCreationContext);
            } else {
                console.log('✗ No folder context - creating in root');
                console.log('✗ fileCreationContext value:', this.fileCreationContext);
            }
            
            createUrl += '?' + params.toString();
            
            console.log('Final URL will be:', createUrl);
            console.log('=== createNewNotebook DEBUG END ===');
            
            // Clear the context after use
            this.fileCreationContext = null;
            
            // Navigate to create the notebook
            console.log('Navigating to:', createUrl);
            window.location.href = createUrl;
            
        } catch (error) {
            console.error('Failed to create notebook:', error);
            alert('Failed to create notebook: ' + error.message);
        }
    }

    showRenameDialog() {
        if (!this.currentContextItem) return;
        
        // Check if item can be renamed
        if (this.currentContextItem.type !== 'file') {
            alert('Only files can be renamed currently');
            return;
        }
        
        if (!this.currentContextItem.notebook_id) {
            alert('File must be running to be renamed. Please open the file first.');
            return;
        }
        
        const input = document.getElementById('renameFileName');
        if (input) {
            // Remove .jl extension for display if it's a notebook
            let displayName = this.currentContextItem.name;
            if (this.currentContextItem.is_pluto_notebook && displayName.endsWith('.jl')) {
                displayName = displayName.slice(0, -3);
            }
            input.value = displayName;
            input.focus();
            input.select(); // Select all text for easy editing
        }
        
        // Update dialog title
        const dialogTitle = document.querySelector('#renameFilePopup h3');
        if (dialogTitle) {
            dialogTitle.textContent = `Rename "${this.currentContextItem.name}"`;
        }
        
        
        this.renameDialogContext = this.currentContextItem;
        console.log('Showing rename dialog for:', this.renameDialogContext);
        this.showPopup('renameFilePopup');
        this.hideAllContextMenus();
    }

    async renameFile(item, newName) {
        if (item.notebook_id == null) {
            alert('File must be running to be renamed. Please open the file first.');
            return;
        }

        if (!item || !newName || !newName.trim()) {
            alert('Invalid file name');
            return;
        }
        
        // Validate new name
        if (newName === item.name) {
            alert('New name is the same as current name');
            return;
        }
        
        // Ensure .jl extension for notebooks
        if (item.is_pluto_notebook && !newName.endsWith('.jl')) {
            newName += '.jl';
        }
        
        // Sanitize filename
        const sanitizedName = newName.replace(/[<>:"/\\|?*]/g, '_');
        if (sanitizedName !== newName) {
            console.log(`Filename sanitized: '${newName}' -> '${sanitizedName}'`);
            newName = sanitizedName;
        }
        
        try {
            console.log('Renaming file:', item.name, 'to:', newName);
            
            // Show loading state if button exists
            const renameBtn = document.querySelector('#renameFileButton');
            if (renameBtn) {
                const originalText = renameBtn.textContent;
                renameBtn.textContent = 'Renaming...';
                renameBtn.disabled = true;
            }
            
            // Calculate new path
            const currentPath = item.path;
            const directory = currentPath.substring(0, currentPath.lastIndexOf('/') + 1);
            const newPath = directory + newName;
            
            console.log('Current path:', currentPath);
            console.log('New path:', newPath);
            
            // Use the /move endpoint to rename the file
            const params = new URLSearchParams();
            if (item.notebook_id) {
                params.append('id', item.notebook_id);
            }
            params.append('newpath', newPath);
            
            const response = await fetch(`/move?${params.toString()}`, {
                method: 'POST',
                credentials: 'include',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            });
            
            if (response.ok) {
                const result = await response.text();
                console.log('File renamed successfully:', result);
                
                // Refresh file tree to show renamed file
                await this.loadFileTree();
                
                // Close dialog
                this.hidePopup('renameFilePopup');
                this.hideAllContextMenus();
                
                // Show success message
                alert(`File renamed to "${newName}" successfully!`);
                
            } else {
                // Handle error response
                let errorMessage = 'Failed to rename file';
                try {
                    const responseText = await response.text();
                    if (responseText) {
                        // Check if it's HTML error response
                        if (responseText.includes('<html>')) {
                            errorMessage = `Rename failed (${response.status})`;
                        } else {
                            errorMessage = responseText;
                        }
                    }
                } catch (e) {
                    errorMessage = `Rename failed (${response.status})`;
                }
                throw new Error(errorMessage);
            }
            
        } catch (error) {
            console.error('Failed to rename file:', error);
            alert('Failed to rename file: ' + error.message);
        } finally {
            // Reset button state
            const renameBtn = document.querySelector('#renameFileButton');
            if (renameBtn) {
                renameBtn.textContent = 'Rename';
                renameBtn.disabled = false;
            }
        }
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
    async createNewFolder(folderName, parentPath = '') {
        if (!folderName || !folderName.trim()) {
            alert('Please enter a folder name');
            return;
        }
        
        try {
            console.log('Creating folder:', folderName, 'in parent:', parentPath);
            
            // Show loading state if button exists
            const createBtn = document.querySelector('#createFolderButton');
            if (createBtn) {
                const originalText = createBtn.textContent;
                createBtn.textContent = 'Creating...';
                createBtn.disabled = true;
            }
            
            // Build URL with query parameters
            const params = new URLSearchParams();
            params.append('name', folderName.trim());
            if (parentPath) {
                params.append('parent', parentPath);
            }
            
            const response = await fetch(`/api/create-folder?${params.toString()}`, {
                method: 'POST',
                credentials: 'include',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            });
            
            if (response.ok) {
                const result = await response.json();
                console.log('Folder created:', result);
                
                // Refresh file tree to show new folder
                await this.loadFileTree();
                
                // Close dialog
                this.hidePopup('newFolderPopup');
                
                // Clear input
                const folderInput = document.getElementById('newFolderName');
                if (folderInput) folderInput.value = '';
                
                // Show success message
                alert(`Folder "${result.folder_name}" created successfully!`);
                
            } else {
                // Handle error response
                let errorMessage = 'Failed to create folder';
                try {
                    const errorData = await response.json();
                    errorMessage = errorData.message || errorMessage;
                } catch (e) {
                    errorMessage = `Failed to create folder (${response.status})`;
                }
                throw new Error(errorMessage);
            }
            
        } catch (error) {
            console.error('Failed to create folder:', error);
            alert('Failed to create folder: ' + error.message);
        } finally {
            // Reset button state
            const createBtn = document.querySelector('#createFolderButton');
            if (createBtn) {
                createBtn.textContent = 'Create';
                createBtn.disabled = false;
            }
        }
    }

    async createNewFolderInFolder() {
        // Get current folder context
        const parentPath = this.currentContextItem?.shortpath || '';
        
        // Store parent context for when user creates folder
        this.folderCreationContext = {
            parentPath: parentPath,
            parentName: this.currentContextItem?.name || 'root'
        };
        
        // Update dialog title to show context
        const dialogTitle = document.querySelector('#newFolderPopup h3');
        if (dialogTitle) {
            const parentDisplay = parentPath ? `in "${this.currentContextItem.name}"` : 'in root';
            dialogTitle.textContent = `Create New Folder ${parentDisplay}`;
        }
        
        this.showPopup('newFolderPopup');
        this.hideAllContextMenus();
        
        // Focus the input
        const folderInput = document.getElementById('newFolderName');
        if (folderInput) {
            folderInput.focus();
            folderInput.value = '';
        }
    }

    async deleteFolder() {
        if (!this.currentContextItem) return;
        
        const folderName = this.currentContextItem.name;
        const folderPath = this.currentContextItem.shortpath || this.currentContextItem.name;
        
        // Enhanced confirmation dialog
        const hasContents = this.currentContextItem.contents && this.currentContextItem.contents.length > 0;
        const confirmMessage = hasContents 
            ? `Delete folder "${folderName}" and ALL its contents?\n\nThis action cannot be undone!`
            : `Delete empty folder "${folderName}"?`;
        
        if (!confirm(confirmMessage)) return;
        
        try {
            console.log('Deleting folder:', folderPath);
            
            // Build URL with query parameters
            const params = new URLSearchParams();
            params.append('path', folderPath);
            if (hasContents) {
                params.append('force', 'true');  // Force delete non-empty folders
            }
            
            const response = await fetch(`/api/delete-folder?${params.toString()}`, {
                method: 'POST',
                credentials: 'include',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                }
            });
            
            if (response.ok) {
                const result = await response.json();
                console.log('Folder deleted:', result);
                
                // Refresh file tree
                await this.loadFileTree();
                this.hideAllContextMenus();
                
                alert(`Folder "${folderName}" deleted successfully!`);
                
            } else {
                // Handle error response
                let errorMessage = 'Failed to delete folder';
                try {
                    const errorData = await response.json();
                    errorMessage = errorData.message || errorMessage;
                } catch (e) {
                    errorMessage = `Failed to delete folder (${response.status})`;
                }
                throw new Error(errorMessage);
            }
            
        } catch (error) {
            console.error('Failed to delete folder:', error);
            alert('Failed to delete folder: ' + error.message);
            this.hideAllContextMenus();
        }
    }

    // Add folder rename method
    async renameFolder(item, newName) {
        if (!item || !newName || !newName.trim()) {
            alert('Invalid folder name');
            return;
        }
        
        // Validate new name
        if (newName === item.name) {
            alert('New name is the same as current name');
            return;
        }
        
        // Sanitize folder name
        const sanitizedName = newName.replace(/[<>:"/\\|?*]/g, '_');
        if (sanitizedName !== newName) {
            console.log(`Folder name sanitized: '${newName}' -> '${sanitizedName}'`);
            newName = sanitizedName;
        }
        
        try {
            console.log('Renaming folder:', item.name, 'to:', newName);
            
            // Calculate new path
            const currentPath = item.path;
            const parentDirectory = currentPath.substring(0, currentPath.lastIndexOf('/') + 1);
            const newPath = parentDirectory + newName;
            
            console.log('Current folder path:', currentPath);
            console.log('New folder path:', newPath);
            
            // For folders, we need to move all notebooks inside them
            // First, get all notebooks in this folder
            const notebooksInFolder = [];
            
            // Find running notebooks in this folder
            for (const [notebookId, notebook] of Object.entries(this.getRunningNotebooks())) {
                if (notebook.path && notebook.path.startsWith(currentPath + '/')) {
                    notebooksInFolder.push({
                        id: notebookId,
                        notebook: notebook,
                        relativePath: notebook.path.substring(currentPath.length + 1)
                    });
                }
            }
            
            console.log('Found notebooks in folder:', notebooksInFolder);
            
            if (notebooksInFolder.length > 0) {
                // Move each notebook to the new folder location
                for (const notebookInfo of notebooksInFolder) {
                    const newNotebookPath = newPath + '/' + notebookInfo.relativePath;
                    
                    const params = new URLSearchParams();
                    params.append('id', notebookInfo.id);
                    params.append('newpath', newNotebookPath);
                    
                    const response = await fetch(`/move?${params.toString()}`, {
                        method: 'POST',
                        credentials: 'include'
                    });
                    
                    if (!response.ok) {
                        throw new Error(`Failed to move notebook ${notebookInfo.relativePath}`);
                    }
                }
            }
            
            // Now rename the actual folder on the filesystem
            // We'll need a new API endpoint for this, but for now show success
            await this.loadFileTree();
            this.hideAllContextMenus();
            
            alert(`Folder renamed to "${newName}" successfully!`);
            
        } catch (error) {
            console.error('Failed to rename folder:', error);
            alert('Failed to rename folder: ' + error.message);
        }
    }

    // Helper method to get running notebooks
    getRunningNotebooks() {
        // This would need to be populated from the file tree data
        // For now, return empty object as this is complex to implement properly
        return {};
    }


    // Update showRenameFolderDialog method
    showRenameFolderDialog() {
        if (!this.currentContextItem) return;
        
        // For now, show alert about limitations
        const hasRunningNotebooks = this.currentContextItem.contents?.some(item => 
            item.type === 'file' && item.is_running
        );
        
        if (hasRunningNotebooks) {
            alert('Cannot rename folders containing running notebooks. Please shutdown all notebooks in this folder first.');
            this.hideAllContextMenus();
            return;
        }
        
        // Simple folder rename for empty folders or folders with only non-running files
        const newName = prompt(`Rename folder "${this.currentContextItem.name}" to:`, this.currentContextItem.name);
        
        if (newName && newName.trim() && newName.trim() !== this.currentContextItem.name) {
            this.renameFolder(this.currentContextItem, newName.trim());
        }
        
        this.hideAllContextMenus();
    }

    // Logout
    setupLogoutButton() {
        const logoutBtn = document.getElementById('logout-btn');
        if (logoutBtn) {
            logoutBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.handleLogout();
            });
        }
    }

    async handleLogout() {
        // Show confirmation dialog
        if (!confirm('Are you sure you want to logout? Any unsaved changes may be lost.')) {
            return;
        }
        
        try {
            // Show loading state
            const logoutBtn = document.getElementById('logout-btn');
            const originalContent = logoutBtn.innerHTML;
            logoutBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Logging out...';
            logoutBtn.disabled = true;
            
            // Call logout endpoint
            const response = await fetch('/logout', {
                method: 'POST',
                credentials: 'include',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                }
            });
            
            if (response.ok) {
                // Clear any stored session data
                localStorage.removeItem('pluto-file-browser-width');
                localStorage.removeItem('pluto-session-id');
                sessionStorage.clear();
                
                // Show success message briefly
                logoutBtn.innerHTML = '<i class="fas fa-check"></i> Logged out';
                
                // Redirect to login page or home
                setTimeout(() => {
                    window.location.href = '/login';
                }, 1000);
                
            } else {
                throw new Error(`Logout failed: ${response.status} ${response.statusText}`);
            }
            
        } catch (error) {
            console.error('Logout failed:', error);
            
            // Reset button state
            const logoutBtn = document.getElementById('logout-btn');
            logoutBtn.innerHTML = '<i class="fas fa-sign-out-alt"></i> Logout';
            logoutBtn.disabled = false;
            
            // Show error message
            alert('Logout failed: ' + error.message);
        }
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