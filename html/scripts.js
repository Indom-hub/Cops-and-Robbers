// html/scripts.js
// Handles NUI interactions for Cops and Robbers game mode.

window.cnrResourceName = 'cops-and-robbers'; // Default fallback, updated by Lua

// =================================================================---
// NUI Message Handling & Security
// =================================================================---

// Allowed origins: include your resource's NUI origin and any other trusted domains.
// Note: Using a dynamic value for allowedOrigins based on window.cnrResourceName here can be tricky
// because window.cnrResourceName might not be set when this script is initially parsed.
// For highest security, the origin check should be robust. If needed, re-evaluate this.
// For now, we'll assume client.lua sends the resource name early.
const allowedOrigins = [
    // This will be checked against event.origin. Since event.origin will be literal like 'nui://actual_resource_name',
    // we might need a more dynamic check or ensure cnrResourceName is set before any critical message processing.
    // For simplicity in this step, we'll rely on the subsequent data.resourceName to set window.cnrResourceName.
    `nui://cops-and-robbers`, // Fallback, actual check might need to be more dynamic or use a wildcard if possible (less secure)
    "http://localhost:3000",
    "nui://game"
];


window.addEventListener('message', function(event) {
    // Dynamic origin check using the potentially updated cnrResourceName
    const currentResourceOrigin = `nui://${window.cnrResourceName || 'cops-and-robbers'}`;
    if (!allowedOrigins.includes(event.origin) && event.origin !== currentResourceOrigin) {
        console.warn(`Security: Received message from untrusted origin: ${event.origin}. Expected: ${currentResourceOrigin} or predefined. Ignoring.`);
        return;
    }
  
    const data = event.data;
  
    switch (data.action) {
        case 'showRoleSelection':
            if (data.resourceName) {
                window.cnrResourceName = data.resourceName;
                console.log("NUI: Resource name set via showRoleSelection to: " + window.cnrResourceName);
                // Update allowedOrigins if it needs to be dynamic and if this is the first time setting it
                if (!allowedOrigins.includes(`nui://${window.cnrResourceName}`)) {
                    allowedOrigins.push(`nui://${window.cnrResourceName}`);
                }
            }
            showRoleSelection();
            break;
        case 'updateMoney':
            updateCashDisplay(data.cash);
            break;
        case 'showStoreMenu': // Assuming store menu might also be an initial display point for some users
            if (data.resourceName) { // If Lua sends resourceName with this action
                window.cnrResourceName = data.resourceName;
                console.log("NUI: Resource name set via showStoreMenu to: " + window.cnrResourceName);
                if (!allowedOrigins.includes(`nui://${window.cnrResourceName}`)) {
                    allowedOrigins.push(`nui://${window.cnrResourceName}`);
                }
            }
            openStoreMenu(data.storeName, data.items);
            break;
        case 'closeStore':
            closeStoreMenu();
            break;
        case 'startHeistTimer':
            startHeistTimer(data.duration, data.bankName);
            break;
        case 'updateXPBar':
            updateXPDisplayElements(data.currentXP, data.currentLevel, data.xpForNextLevel);
            break;
        case 'refreshSellListIfNeeded':
            const storeMenu = document.getElementById('store-menu');
            if (storeMenu && storeMenu.style.display === 'block' && window.currentTab === 'sell') {
                console.log("Refreshing sell list due to inventory update:", data.inventory);
                const sellableItems = [];
                for (const itemId in data.inventory) {
                    const item = data.inventory[itemId];
                    sellableItems.push({
                        itemId: itemId,
                        name: item.name,
                        count: item.count,
                        category: item.category,
                        sellPrice: item.sellPrice
                    });
                }
                const sellListContainer = document.getElementById('sell-section');
                if (sellListContainer) {
                    sellListContainer.innerHTML = '';
                    if (sellableItems.length === 0) {
                        sellListContainer.innerHTML = '<p style="text-align: center;">Your inventory is empty.</p>';
                    } else {
                        const fragment = document.createDocumentFragment();
                        sellableItems.forEach(invItem => {
                            fragment.appendChild(createItemElement(invItem, 'sell'));
                        });
                        sellListContainer.appendChild(fragment);
                    }
                }
            }
            break;
        case 'showAdminPanel':
            if (data.resourceName) {
                window.cnrResourceName = data.resourceName;
                console.log("NUI: Resource name set via showAdminPanel to: " + window.cnrResourceName);
                 if (!allowedOrigins.includes(`nui://${window.cnrResourceName}`)) {
                    allowedOrigins.push(`nui://${window.cnrResourceName}`);
                }
            }
            showAdminPanel(data.players);
            break;
        case 'showBountyBoard': // Added case for bounty board
            if (data.resourceName) {
                window.cnrResourceName = data.resourceName;
                console.log("NUI: Resource name set via showBountyBoard to: " + window.cnrResourceName);
                if (!allowedOrigins.includes(`nui://${window.cnrResourceName}`)) {
                    allowedOrigins.push(`nui://${window.cnrResourceName}`);
                }
            }
            // Assuming a function showBountyBoardUI(bounties) exists or will be created
            if (typeof showBountyBoardUI === 'function') {
                showBountyBoardUI(data.bounties);
            } else {
                console.warn("showBountyBoardUI function not implemented in JS yet.");
            }
            break;
        case 'hideBountyBoard': // Added case for bounty board
             if (typeof hideBountyBoardUI === 'function') {
                hideBountyBoardUI();
            } else {
                console.warn("hideBountyBoardUI function not implemented in JS yet.");
            }
            break;
        case 'updateBountyList': // Added case for bounty board
             if (typeof updateBountyListUI === 'function') {
                updateBountyListUI(data.bounties);
            } else {
                console.warn("updateBountyListUI function not implemented in JS yet.");
            }
            break;
        default:
            console.warn(`Unhandled NUI action: ${data.action}`);
    }
});

// =================================================================---
// NUI Focus Helper Function
// =================================================================---
async function fetchSetNuiFocus(hasFocus, hasCursor) {
    try {
        console.log('[CNR_NUI] Inside fetchSetNuiFocus. window.cnrResourceName:', window.cnrResourceName);
        const resName = window.cnrResourceName || 'cops-and-robbers'; // Ensure resName is correctly defined based on window.cnrResourceName

        // Ensure this log uses backticks and resName is defined in this scope
        console.log(`[CNR_NUI] Attempting to fetchSetNuiFocus. Resource: ${resName}, URL: https://${resName}/setNuiFocus`);

        await fetch(`https://${resName}/setNuiFocus`, { // Ensure this is a template literal with backticks
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ hasFocus: hasFocus, hasCursor: hasCursor })
        });
    } catch (error) {
        // Update the error log for clarity and ensure it also uses resName if needed for context
        const resNameForError = window.cnrResourceName || 'cops-and-robbers'; // Recapture for error message just in case
        console.error(`Error calling setNuiFocus NUI callback (URL attempted: https://${resNameForError}/setNuiFocus):`, error);
    }
}

// =================================================================---
// XP Level Display Functions
// =================================================================---
function updateXPDisplayElements(xp, level, nextLvlXp) {
    const levelTextElement = document.getElementById('level-text');
    const xpTextElement = document.getElementById('xp-text');
    const xpBarFillElement = document.getElementById('xp-bar-fill');
    const xpLevelContainer = document.getElementById('xp-level-container');

    if (xpLevelContainer) xpLevelContainer.style.display = 'flex';
    if (levelTextElement) levelTextElement.textContent = "LVL " + level;
    if (xpTextElement) xpTextElement.textContent = xp + " / " + nextLvlXp + " XP";
    if (xpBarFillElement) {
        let percentage = 0;
        if (typeof nextLvlXp === 'number' && nextLvlXp > 0 && xp < nextLvlXp) {
            percentage = (xp / nextLvlXp) * 100;
        } else if (typeof nextLvlXp !== 'number' || xp >= nextLvlXp) {
            percentage = 100;
        }
        xpBarFillElement.style.width = Math.max(0, Math.min(100, percentage)) + '%';
    }
}

function updateCashDisplay(currentCash) {
    const cashDisplayElement = document.getElementById('cash-display');
    if (cashDisplayElement) {
        cashDisplayElement.textContent = '$' + (currentCash !== undefined ? currentCash.toLocaleString() : '0');
        cashDisplayElement.style.display = 'block';
    } else {
        console.error("Cash display element 'cash-display' not found in HTML.");
    }
}

// =================================================================---
// UI Visibility Functions (Role Selection & Store)
// =================================================================---
function showRoleSelection() {
    const roleSelectionUI = document.getElementById('role-selection');
    if (roleSelectionUI) {
        roleSelectionUI.style.display = 'block';
        fetchSetNuiFocus(true, true);
    } else {
        console.error("Role selection UI element not found.");
    }
}

function hideRoleSelection() {
    const roleSelectionUI = document.getElementById('role-selection');
    if (roleSelectionUI) {
        roleSelectionUI.style.display = 'none';
        fetchSetNuiFocus(false, false);
    }
}

function openStoreMenu(storeName, storeItems) {
    const storeMenuUI = document.getElementById('store-menu');
    const storeTitleEl = document.getElementById('store-title');
    if (storeMenuUI && storeTitleEl) {
        storeTitleEl.textContent = storeName || 'Store';
        window.items = storeItems || [];
        window.currentCategory = null;
        window.currentTab = 'buy';
        loadCategories();
        loadItems();
        storeMenuUI.style.display = 'block';
        fetchSetNuiFocus(true, true);
    } else {
        console.error("Store menu UI or title element not found.");
    }
}

function closeStoreMenu() {
    const storeMenuUI = document.getElementById('store-menu');
    if (storeMenuUI) {
        storeMenuUI.style.display = 'none';
        fetchSetNuiFocus(false, false);
    }
}

// =================================================================---
// Store: Tab and Category Management & Item Creation/Interaction
// =================================================================---
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        window.currentTab = btn.dataset.tab;
        document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
        const activeTabContent = document.getElementById(`${window.currentTab}-section`);
        if (activeTabContent) activeTabContent.classList.add('active');
        if (window.currentTab === 'sell') loadSellItems();
        else loadItems();
    });
});

function loadCategories() {
    const categoryList = document.getElementById('category-list');
    if (!categoryList) return;
    const categories = [...new Set(window.items.map(item => item.category))];
    categoryList.innerHTML = '';
    categories.forEach(category => {
        const btn = document.createElement('button');
        btn.className = 'category-btn';
        btn.textContent = category;
        btn.onclick = () => {
            window.currentCategory = category;
            document.querySelectorAll('.category-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            if (window.currentTab === 'buy') loadItems();
        };
        categoryList.appendChild(btn);
    });
}

function loadItems() {
    const itemList = document.getElementById('item-list');
    if (!itemList) return;
    itemList.innerHTML = '';
    const filteredItems = window.items.filter(item => !window.currentCategory || item.category === window.currentCategory);
    if (filteredItems.length === 0) {
        itemList.innerHTML = '<p style="text-align: center;">No items in this category.</p>';
        return;
    }
    const fragment = document.createDocumentFragment();
    filteredItems.forEach(item => fragment.appendChild(createItemElement(item, 'buy')));
    itemList.appendChild(fragment);
}

function loadSellItems() {
    const sellListContainer = document.getElementById('sell-section');
    if (!sellListContainer) return;
    sellListContainer.innerHTML = '<p style="text-align: center;">Loading inventory...</p>';
    const resName = window.cnrResourceName || 'cops-and-robbers';
    fetch(`https://$\{resName}/getPlayerInventory`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(resp => {
        if (!resp.ok) return resp.json().then(err => Promise.reject(err)).catch(() => Promise.reject({ message: `Failed to load inventory (HTTP ${resp.status})` }));
        return resp.json();
    })
    .then(nuiInventory => {
        sellListContainer.innerHTML = '';
        const sellableItemsArray = Object.values(nuiInventory);
        if (!sellableItemsArray || sellableItemsArray.length === 0) {
            sellListContainer.innerHTML = '<p style="text-align: center;">Your inventory is empty.</p>';
            return;
        }
        const fragment = document.createDocumentFragment();
        sellableItemsArray.forEach(inventoryItem => fragment.appendChild(createItemElement(inventoryItem, 'sell')));
        sellListContainer.appendChild(fragment);
    })
    .catch(error => {
        console.error('Error fetching player inventory:', error.message || error);
        sellListContainer.innerHTML = `<p style="text-align: center; color: red;">Error loading inventory: ${error.message || 'Unknown error'}</p>`;
    });
}

function createItemElement(item, type = 'buy') {
    const itemDiv = document.createElement('div');
    itemDiv.className = 'item';
    itemDiv.dataset.itemId = item.itemId;
    const nameDiv = document.createElement('div');
    nameDiv.className = 'item-name';
    nameDiv.textContent = item.name;
    itemDiv.appendChild(nameDiv);
    if (type === 'sell' && item.count !== undefined) {
        const quantityDiv = document.createElement('div');
        quantityDiv.className = 'item-quantity';
        quantityDiv.textContent = `x${item.count}`;
        itemDiv.appendChild(quantityDiv);
    }
    const priceDiv = document.createElement('div');
    priceDiv.className = 'item-price';
    priceDiv.textContent = `$${(type === 'buy' ? item.price : item.sellPrice)}`;
    itemDiv.appendChild(priceDiv);
    const quantityInput = document.createElement('input');
    quantityInput.type = 'number';
    quantityInput.className = 'quantity-input';
    quantityInput.min = '1';
    quantityInput.max = (type === 'buy') ? '100' : (item.count ? item.count.toString() : '1');
    quantityInput.value = '1';
    itemDiv.appendChild(quantityInput);
    const actionBtn = document.createElement('button');
    actionBtn.className = (type === 'buy') ? 'buy-btn' : 'sell-btn';
    actionBtn.textContent = (type === 'buy') ? 'Buy' : 'Sell';
    actionBtn.dataset.action = type;
    itemDiv.appendChild(actionBtn);
    return itemDiv;
}

async function handleItemAction(itemId, quantity, actionType) {
    const endpoint = actionType === 'buy' ? 'buyItem' : 'sellItem';
    const resName = window.cnrResourceName || 'cops-and-robbers';
    try {
        const resp = await fetch(`https://$\{resName}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ itemId: itemId, quantity: quantity })
        });
        const response = await resp.json();
        if (!resp.ok) throw new Error(response.message || `HTTP error ${resp.status}`);
        if (response.status === 'success') {
            alert(`Successfully ${actionType === 'buy' ? 'purchased' : 'sold'} ${quantity} x ${response.itemName || itemId}`);
            if (actionType === 'sell') loadSellItems();
        } else {
            alert(`${actionType === 'buy' ? 'Purchase' : 'Sell'} failed: ${response.message || 'Unknown error'}`);
        }
    } catch (error) {
        console.error(`Error ${actionType}ing item:`, error.message || error);
        alert(`Failed to ${actionType} item: ${error.message || 'Check console for details.'}`);
    }
}

document.addEventListener('click', function(event) {
    const target = event.target;
    const itemDiv = target.closest('.item');
    if (!itemDiv) return;
    const itemId = itemDiv.dataset.itemId;
    const actionType = target.dataset.action;
    if (itemId && (actionType === 'buy' || actionType === 'sell')) {
        const quantityInput = itemDiv.querySelector('.quantity-input');
        if (!quantityInput) { console.error('Quantity input not found for item:', itemId); return; }
        const quantity = parseInt(quantityInput.value);
        const maxQuantity = parseInt(quantityInput.max);
        if (isNaN(quantity) || quantity < 1 || quantity > maxQuantity) {
            alert(`Invalid quantity. Must be between 1 and ${maxQuantity}.`);
            return;
        }
        handleItemAction(itemId, quantity, actionType);
    }
});

// -------------------------------------------------------------------
// Role Selection and Initialization
// -------------------------------------------------------------------
function selectRole(selectedRole) {
    const resName = window.cnrResourceName || 'cops-and-robbers';
    fetch(`https://$\{resName}/selectRole`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ role: selectedRole })
    })
    .then(resp => resp.json())
    .then(response => {
        if (response.status === 'success') {
            alert(`Role set to ${response.role}`);
            hideRoleSelection();
        } else {
            alert(`Role selection failed: ${response.message}`);
        }
    })
    .catch(error => {
        console.error('Error selecting role:', error);
        alert('Failed to select role.');
    });
}

document.addEventListener('DOMContentLoaded', () => {
    const roleSelectionContainer = document.getElementById('role-selection');
    if (roleSelectionContainer) {
        roleSelectionContainer.addEventListener('click', function(event) {
            const button = event.target.closest('button[data-role]');
            if (button) selectRole(button.getAttribute('data-role'));
        });
    } else {
        document.querySelectorAll('.menu button[data-role]').forEach(button => {
            button.addEventListener('click', () => selectRole(button.getAttribute('data-role')));
        });
    }

    const adminPlayerListBody = document.getElementById('admin-player-list-body');
    if (adminPlayerListBody) {
        adminPlayerListBody.addEventListener('click', function(event) {
            const target = event.target;
            if (target.classList.contains('admin-action-btn')) {
                const targetId = target.dataset.targetId;
                if (!targetId) return;
                const resName = window.cnrResourceName || 'cops-and-robbers';
                if (target.classList.contains('admin-kick-btn')) {
                    if (confirm(`Kick player ID ${targetId}?`)) {
                        fetch(`https://$\{resName}/adminKickPlayer`, {
                            method: 'POST', headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ targetId: targetId })
                        }).then(resp => resp.json()).then(res => alert(res.message || (res.status === 'ok' ? 'Kicked.' : 'Failed.')));
                    }
                } else if (target.classList.contains('admin-ban-btn')) {
                    currentAdminTargetPlayerId = targetId;
                    document.getElementById('admin-ban-reason-container')?.classList.remove('hidden');
                    document.getElementById('admin-ban-reason')?.focus();
                } else if (target.classList.contains('admin-teleport-btn')) {
                    if (confirm(`Teleport to player ID ${targetId}?`)) {
                         fetch(`https://$\{resName}/teleportToPlayerAdminUI`, {
                            method: 'POST', headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ targetId: targetId })
                        }).then(resp => resp.json()).then(res => {
                            alert(res.message || (res.status === 'ok' ? 'Teleporting.' : 'Failed.'));
                            hideAdminPanel();
                        });
                    }
                }
            }
        });
    }

    document.getElementById('admin-confirm-ban-btn')?.addEventListener('click', function() {
        if (currentAdminTargetPlayerId) {
            const reasonInput = document.getElementById('admin-ban-reason');
            const reason = reasonInput ? reasonInput.value.trim() : "Banned by Admin via UI.";
            const resName = window.cnrResourceName || 'cops-and-robbers';
            fetch(`https://$\{resName}/adminBanPlayer`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ targetId: currentAdminTargetPlayerId, reason: reason })
            }).then(resp => resp.json()).then(res => {
                alert(res.message || (res.status === 'ok' ? 'Banned.' : 'Failed.'));
                hideAdminPanel();
            });
        }
    });

    document.getElementById('admin-cancel-ban-btn')?.addEventListener('click', function() {
        document.getElementById('admin-ban-reason-container')?.classList.add('hidden');
        const banReasonInput = document.getElementById('admin-ban-reason');
        if (banReasonInput) banReasonInput.value = '';
        currentAdminTargetPlayerId = null;
    });

    document.getElementById('admin-close-btn')?.addEventListener('click', hideAdminPanel);

    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            window.currentTab = btn.dataset.tab;
            document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
            const activeTabContent = document.getElementById(`${window.currentTab}-section`);
            if (activeTabContent) activeTabContent.classList.add('active');
            if (window.currentTab === 'sell') loadSellItems();
            else loadItems();
        });
    });
});

// -------------------------------------------------------------------
// Heist Timer Functionality
// -------------------------------------------------------------------
let heistTimerInterval = null;
function startHeistTimer(duration, bankName) {
    const heistTimerEl = document.getElementById('heist-timer');
    if (!heistTimerEl) { console.warn('#heist-timer element not found.'); return; }
    heistTimerEl.style.display = 'block';
    const timerTextEl = document.getElementById('timer-text');
    if (!timerTextEl) { console.warn('#timer-text element not found.'); heistTimerEl.style.display = 'none'; return; }
    let remainingTime = duration;
    timerTextEl.textContent = `Heist at ${bankName}: ${formatTime(remainingTime)}`;
    if (heistTimerInterval) clearInterval(heistTimerInterval);
    heistTimerInterval = setInterval(function() {
        remainingTime--;
        if (remainingTime <= 0) {
            clearInterval(heistTimerInterval);
            heistTimerInterval = null;
            heistTimerEl.style.display = 'none';
            return;
        }
        timerTextEl.textContent = `Heist at ${bankName}: ${formatTime(remainingTime)}`;
    }, 1000);
}

function formatTime(seconds) {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
}

// =================================================================---
// Admin Panel Functions
// =================================================================---
let currentAdminTargetPlayerId = null;
function showAdminPanel(playerList) {
    const adminPanel = document.getElementById('admin-panel');
    const playerListBody = document.getElementById('admin-player-list-body');
    if (!adminPanel || !playerListBody) { console.error("Admin panel elements not found."); return; }
    playerListBody.innerHTML = '';
    if (playerList && playerList.length > 0) {
        playerList.forEach(player => {
            const row = playerListBody.insertRow();
            row.insertCell().textContent = player.name;
            row.insertCell().textContent = player.serverId;
            row.insertCell().textContent = player.role;
            row.insertCell().textContent = '$' + (player.cash || 0);
            const actionsCell = row.insertCell();
            const kickBtn = document.createElement('button');
            kickBtn.textContent = 'Kick'; kickBtn.className = 'admin-action-btn admin-kick-btn';
            kickBtn.dataset.targetId = player.serverId; actionsCell.appendChild(kickBtn);
            const banBtn = document.createElement('button');
            banBtn.textContent = 'Ban'; banBtn.className = 'admin-action-btn admin-ban-btn';
            banBtn.dataset.targetId = player.serverId; actionsCell.appendChild(banBtn);
            const teleportBtn = document.createElement('button');
            teleportBtn.textContent = 'TP to'; teleportBtn.className = 'admin-action-btn admin-teleport-btn';
            teleportBtn.dataset.targetId = player.serverId; actionsCell.appendChild(teleportBtn);
        });
    } else {
        playerListBody.innerHTML = '<tr><td colspan="5" style="text-align:center;">No players online or data unavailable.</td></tr>';
    }
    adminPanel.classList.remove('hidden');
    fetchSetNuiFocus(true, true);
}

function hideAdminPanel() {
    const adminPanel = document.getElementById('admin-panel');
    if (adminPanel) adminPanel.classList.add('hidden');
    const banReasonContainer = document.getElementById('admin-ban-reason-container');
    if (banReasonContainer) banReasonContainer.classList.add('hidden');
    const banReasonInput = document.getElementById('admin-ban-reason');
    if (banReasonInput) banReasonInput.value = '';
    currentAdminTargetPlayerId = null;
    fetchSetNuiFocus(false, false);
}

// Added missing UI functions for bounty board based on NUI messages
function showBountyBoardUI(bounties) {
    // Placeholder: Implement actual UI display logic for bounty board
    console.log("Attempting to show bounty board UI with bounties:", bounties);
    const bountyBoardElement = document.getElementById('bounty-board'); // Assuming an element with this ID exists
    if (bountyBoardElement) {
        bountyBoardElement.style.display = 'block'; // Or 'flex', etc.
        updateBountyListUI(bounties); // Populate it
        fetchSetNuiFocus(true, true);
    } else {
        console.warn("Bounty board UI element not found.");
    }
}

function hideBountyBoardUI() {
    // Placeholder: Implement actual UI hiding logic
    console.log("Attempting to hide bounty board UI.");
    const bountyBoardElement = document.getElementById('bounty-board');
    if (bountyBoardElement) {
        bountyBoardElement.style.display = 'none';
        fetchSetNuiFocus(false, false);
    }
}

function updateBountyListUI(bounties) {
    // Placeholder: Implement logic to update the bounty list in the UI
    console.log("Updating bounty list UI with:", bounties);
    const bountyListContainer = document.getElementById('bounty-list-container'); // Assuming this ID
    if (bountyListContainer) {
        bountyListContainer.innerHTML = ''; // Clear old bounties
        if (Object.keys(bounties).length === 0) {
            bountyListContainer.innerHTML = '<p>No active bounties.</p>';
            return;
        }
        for (const targetId in bounties) {
            const bounty = bounties[targetId];
            const bountyDiv = document.createElement('div');
            bountyDiv.className = 'bounty-entry';
            bountyDiv.innerHTML = `Target: ${bounty.name} (ID: ${targetId}) - Reward: $${bounty.amount}`;
            // Add more details as needed
            bountyListContainer.appendChild(bountyDiv);
        }
    } else {
        console.warn("Bounty list container element not found for UI update.");
    }
}
