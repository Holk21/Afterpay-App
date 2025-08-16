const app = document.getElementById('app');
const closeBtn = document.getElementById('closeBtn');
const viewCartBtn = document.getElementById('viewCartBtn');
const cartDrawer = document.getElementById('cartDrawer');
const closeCart = document.getElementById('closeCart');

const tabs = document.querySelectorAll('.tab');
const panes = document.querySelectorAll('.pane');

let state = {
  staff: false,
  shops: [],
  plans: [],
  selectedShop: null,
  catalog: [],
  cart: [],
  orders: []
};

function nuiPost(name, data = {}) {
  return fetch(`https://qb-afterpay/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(r => r.json());
}

function openUI(opts) {
  state.staff = !!opts.staff;
  document.querySelector('.staff-only').style.display = state.staff ? 'inline-block' : 'none';
  app.classList.remove('hidden');
  loadShops();
  hydratePlans(opts.plans || []);
  loadOrders();
}

function closeUI() {
  app.classList.add('hidden');
  nuiPost('close', {});
}

tabs.forEach(t => t.addEventListener('click', () => {
  tabs.forEach(x => x.classList.remove('active'));
  t.classList.add('active');
  panes.forEach(p => p.classList.remove('active'));
  document.getElementById(t.dataset.tab).classList.add('active');
  if (t.dataset.tab === 'orders') loadOrders();
  if (t.dataset.tab === 'staff') renderStaff();
}));

closeBtn.addEventListener('click', closeUI);
viewCartBtn.addEventListener('click', () => cartDrawer.classList.add('open'));
closeCart.addEventListener('click', () => cartDrawer.classList.remove('open'));

const shopSelect = document.getElementById('shopSelect');
const planSelect = document.getElementById('planSelect');
const catalogGrid = document.getElementById('catalogGrid');
const cartList = document.getElementById('cartList');
const cartCount = document.getElementById('cartCount');
const totalEl = document.getElementById('total');
const perPaymentEl = document.getElementById('perPayment');
const checkoutBtn = document.getElementById('checkoutBtn');

shopSelect.addEventListener('change', () => {
  state.selectedShop = shopSelect.value;
  loadCatalog();
});

checkoutBtn.addEventListener('click', () => {
  if (!state.selectedShop) return notify('Choose a shop first');
  if (state.cart.length === 0) return notify('Your cart is empty');
  const plan_id = planSelect.value;
  nuiPost('checkout', { shop_id: state.selectedShop, items: state.cart, plan_id });
  state.cart = [];
  renderCart();
  loadOrders();
});

function loadShops() {
  nuiPost('getShops').then(shops => {
    state.shops = shops || [];
    renderShopSelect();
  });
}

function hydratePlans(plans) {
  state.plans = plans || [];
  renderPlans();
}

function renderShopSelect() {
  shopSelect.innerHTML = '';
  const staffShop = document.getElementById('staffShop');
  if (staffShop) staffShop.innerHTML = '';
  state.shops.forEach(s => {
    const opt = document.createElement('option'); opt.value = s.id; opt.textContent = s.label; shopSelect.appendChild(opt);
    if (staffShop){ const opt2 = document.createElement('option'); opt2.value = s.id; opt2.textContent = s.label; staffShop.appendChild(opt2); }
  });
  if (state.shops[0]) {
    shopSelect.value = state.shops[0].id;
    state.selectedShop = state.shops[0].id;
    loadCatalog();
  }
}

function renderPlans() {
  planSelect.innerHTML = '';
  state.plans.forEach(p => {
    const opt = document.createElement('option'); opt.value = p.id; opt.textContent = p.label; planSelect.appendChild(opt);
  });
  if (state.plans[0]) planSelect.value = state.plans[0].id;
}

function loadCatalog() {
  nuiPost('getCatalog', { shop_id: state.selectedShop }).then(items => {
    state.catalog = items || [];
    renderCatalog();
    renderStaff();
  });
}

function renderCatalog() {
  catalogGrid.innerHTML = '';
  state.catalog.forEach(it => {
    const card = document.createElement('div');
    card.className = 'product';
    const per = installmentsAmount(it.price);
    card.innerHTML = `
      <div class="img">${it.image_url ? `<img src="${it.image_url}">` : ''}</div>
      <div class="meta">
        <div class="title">${it.label}</div>
        <div class="muted">${it.name}</div>
        <div class="price">$${it.price}</div>
        <div class="muted">${per.parts} payments of $${per.amount}</div>
      </div>
      <div class="actions">
        <input class="qty" type="number" min="1" value="1">
        <button class="primary add">Add</button>
      </div>`;
    const qtyInput = card.querySelector('.qty');
    card.querySelector('.add').addEventListener('click', () => {
      addToCart({ name: it.name, label: it.label, price: it.price, qty: parseInt(qtyInput.value || '1') });
    });
    catalogGrid.appendChild(card);
  });
}

function installmentsAmount(price){
  const plan = state.plans.find(p => p.id === planSelect.value) || { parts: 4 };
  const part = Math.round((price / (plan.parts || 4)));
  return { parts: plan.parts || 4, amount: part };
}

function addToCart(item) {
  const existing = state.cart.find(x => x.name === item.name);
  if (existing) existing.qty += item.qty;
  else state.cart.push(item);
  renderCart();
  cartDrawer.classList.add('open');
}

function renderCart() {
  cartList.innerHTML = '';
  let total = 0;
  state.cart.forEach((it, idx) => {
    total += it.price * it.qty;
    const li = document.createElement('li');
    li.innerHTML = `<div><strong>${it.label}</strong> x ${it.qty}</div>
                    <button data-idx="${idx}" class="ghost">Remove</button>`;
    cartList.appendChild(li);
  });
  cartList.querySelectorAll('button[data-idx]').forEach(b=>{
    b.addEventListener('click', () => { state.cart.splice(parseInt(b.dataset.idx),1); renderCart(); });
  });
  cartCount.textContent = state.cart.reduce((a,b)=>a+b.qty,0);
  totalEl.textContent = total.toFixed(0);
  const per = installmentsAmount(total || 0);
  perPaymentEl.textContent = total ? `${per.parts} payments of $${per.amount}` : '';
}

const ordersList = document.getElementById('ordersList');

function loadOrders() {
  nuiPost('getOrders').then(orders => {
    state.orders = orders || [];
    renderOrders();
  });
}

function renderOrders() {
  ordersList.innerHTML = '';
  state.orders.forEach(o => {
    const li = document.createElement('li');
    let instHtml = '';
    (o.installments || []).forEach(i => {
      const due = new Date(i.due_at).toLocaleString();
      instHtml += `<div class="muted">#${i.id} â€¢ $${i.amount} â€¢ Due ${due} â€¢ ${i.paid ? 'Paid' : '<button data-id="'+i.id+'" class="primary">Pay</button>'}</div>`;
    });
    li.innerHTML = `<div>
      <div><strong>${o.shop_id}</strong> â€¢ $${o.total} â€¢ ${o.status}</div>
      ${instHtml}
    </div>`;
    ordersList.appendChild(li);
  });
  ordersList.querySelectorAll('button[data-id]').forEach(btn => {
    btn.addEventListener('click', () => {
      const id = parseInt(btn.getAttribute('data-id'));
      nuiPost('payInstallment', { installment_id: id });
      setTimeout(loadOrders, 500);
    });
  });
}

const staffShop = document.getElementById('staffShop');
const itemName = document.getElementById('itemName');
const itemLabel = document.getElementById('itemLabel');
const itemPrice = document.getElementById('itemPrice');
const itemImage = document.getElementById('itemImage');
const saveItemBtn = document.getElementById('saveItemBtn');
const staffCatalog = document.getElementById('staffCatalog');

if (saveItemBtn){
  saveItemBtn.addEventListener('click', () => {
    const data = {
      shop_id: staffShop.value,
      name: itemName.value.trim(),
      label: itemLabel.value.trim(),
      price: parseInt(itemPrice.value || '0'),
      image_url: itemImage.value.trim()
    };
    if (!data.name || !data.label || data.price <= 0) return notify('Fill all fields');
    nuiPost('staff:addItem', data);
    setTimeout(loadCatalog, 400);
  });
}

function renderStaff() {
  if (!state.staff) return;
  staffHydratePlansForCO();

  staffCatalog.innerHTML = '';
  state.catalog.forEach(it => {
    const li = document.createElement('li');
    li.innerHTML = `<div><strong>${it.label}</strong> <span class="muted">(${it.name})</span></div>
      <div style="display:flex;gap:6px;align-items:center;">
        <input type="number" min="1" value="${it.price}" style="width:90px;">
        <button class="primary upd">Update</button>
        <button class="ghost del">Delete</button>
      </div>`;
    const priceInput = li.querySelector('input');
    li.querySelector('.upd').addEventListener('click', () => {
      nuiPost('staff:updatePrice', { shop_id: staffShop.value, name: it.name, price: parseInt(priceInput.value || '0') });
      setTimeout(loadCatalog, 400);
    });
    li.querySelector('.del').addEventListener('click', () => {
      nuiPost('staff:removeItem', { shop_id: staffShop.value, name: it.name });
      setTimeout(loadCatalog, 400);
    });
    staffCatalog.appendChild(li);
  });
}

function notify(msg){ console.log('[Afterpay]', msg); }

// ---- Merchant Create Order (staff) ----
const coTarget = document.getElementById('coTarget');
const coItems = document.getElementById('coItems');
const coAddItem = document.getElementById('coAddItem');
const coPlan = document.getElementById('coPlan');
const coCreate = document.getElementById('coCreate');

function staffHydratePlansForCO(){
  if (!coPlan) return;
  coPlan.innerHTML = '';
  (state.plans || []).forEach(p => {
    const o = document.createElement('option');
    o.value = p.id; o.textContent = p.label;
    coPlan.appendChild(o);
  });
}

function coAddLine(initial){
  const row = document.createElement('div');
  row.style = 'display:flex; gap:6px; align-items:center; margin:6px 0;';
  row.innerHTML = `
    <input placeholder="Name (inventory or custom)" style="flex:2">
    <input placeholder="Label" style="flex:2">
    <input type="number" placeholder="Price" style="width:120px">
    <input type="number" placeholder="Qty" value="1" style="width:80px">
    <button class="ghost remove">x</button>
  `;
  row.querySelector('.remove').addEventListener('click', ()=> row.remove());
  if (initial) {
    row.children[0].value = initial.name || '';
    row.children[1].value = initial.label || '';
    row.children[2].value = initial.price || 0;
    row.children[3].value = initial.qty || 1;
  }
  coItems.appendChild(row);
}

if (coAddItem) coAddItem.addEventListener('click', ()=> coAddLine());

if (coCreate){
  coCreate.addEventListener('click', () => {
    const target = parseInt(coTarget.value || '0');
    if (!target) return notify('Enter customer server id');
    const plan_id = coPlan.value;
    const items = [];
    coItems.querySelectorAll('div').forEach(row => {
      const inputs = row.querySelectorAll('input');
      const name = inputs[0].value.trim();
      const label = inputs[1].value.trim();
      const price = parseInt(inputs[2].value || '0');
      const qty = parseInt(inputs[3].value || '1');
      if (label && price > 0 && qty > 0) items.push({ name, label, price, qty });
    });
    if (items.length === 0) return notify('Add at least one line item');

    nuiPost('staff:merchant:createOrder', {
      target_src: target,
      shop_id: staffShop.value,
      plan_id,
      items
    });
    setTimeout(loadOrders, 600);
  });
}

window.addEventListener('message', (e) => {
  const data = e.data || {};
  if (data.action === 'open') {
    openUI({ staff: !!data.staff, plans: data.plans || [] });
  }
});
