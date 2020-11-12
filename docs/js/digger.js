$(document).ready(function()
{
    $('#sort_table').DataTable({
      "paging": false,
      "columnDefs": [
        { "targets": [0, 2], "orderable": true },
        { "targets": "_all", "orderable": false },
      ],
      "order": [[ 2, "desc" ]]
    });
});
