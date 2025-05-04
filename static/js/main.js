document.addEventListener('DOMContentLoaded', () => {
    fetch('/api/stocks')
      .then(response => response.json())
      .then(data => {
        const ul = document.getElementById('stock-list');
        ul.innerHTML = '';  // Clear existing
        data.forEach(s => {
          const li = document.createElement('li');
          li.innerHTML = `
            ${s.company_id} – ${s.company_name}: ${s.description}
            <form action="/delete" method="post" style="display:inline">
              <input type="hidden" name="id" value="${s.id}" />
              <button type="submit">Xóa</button>
            </form>
          `;
          ul.appendChild(li);
        });
      })
      .catch(err => console.error('Lỗi khi lấy dữ liệu:', err));
  });