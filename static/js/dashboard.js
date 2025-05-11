document.addEventListener('DOMContentLoaded', function() {
  fetch('/admin/api/dashboard-data')
    .then(res => res.json())
    .then(data => {
      // Basic
      document.getElementById('todaySales').textContent = data.today_sales;
      document.getElementById('totalSales').textContent = data.total_sales;
      document.getElementById('todayRevenue').textContent = data.today_revenue;
      document.getElementById('totalRevenue').textContent = data.total_revenue;
      // Utility to render series
      function renderChart(id, label, series, type='line') {
        new Chart(document.getElementById(id), {
          type: type,
          data: {
            labels: series.map(pt => pt.date),
            datasets: [{ label: label, data: series.map(pt => pt.count) }]
          }
        });
      }
      // Monitoring
      renderChart('depositsChart', 'Deposits', data.deposits, 'bar');
      renderChart('withdrawalsChart', 'Withdrawals', data.withdrawals, 'bar');
      renderChart('ordersChart', 'Orders', data.orders, 'bar');
      renderChart('transactionsChart', 'Transactions', data.transactions, 'bar');
      // Reports
      renderChart('newUsersChart', 'New Users', data.new_users);
      // Top traded stocks as bar
      new Chart(document.getElementById('topStocksChart'), {
        type: 'bar',
        data: {
          labels: data.summary ? [] : [],
          datasets: data.top_stocks ? [{ label: 'Top Stocks', data: data.top_stocks.map(s => s.volume) }] : []
        },
        options: {
          scales: { x: { labels: data.top_stocks ? data.top_stocks.map(s => s.symbol) : [] } }
        }
      });
    })
    .catch(err => console.error('Lỗi khi lấy dữ liệu:', err));
});
