document.addEventListener('DOMContentLoaded', () => {
    fetch('/api/stocks')
      .then(response => response.json())
      .then(data => {
        const ul = document.getElementById('stock-list');
        ul.innerHTML = '';
        data.forEach(s => {
          const li = document.createElement('li');
          li.textContent = `${s.symbol} – ${s.name}: ${s.price}`;
          ul.appendChild(li);
        });
      })
      .catch(err => console.error('Lỗi khi lấy dữ liệu:', err));
  });