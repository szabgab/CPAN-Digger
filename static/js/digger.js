$(document).ready(function()
{
    $('#sort_table').DataTable({
      "paging": false,
      "columnDefs": [
        { "targets": [0, 1, 2, 7], "orderable": true },
        { "targets": "_all", "orderable": false },
      ],
      "order": [[ 2, "desc" ]]
    });
});
