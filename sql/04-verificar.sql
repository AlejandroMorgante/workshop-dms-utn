SELECT current_database() AS base,
       current_user AS usuario,
       current_setting('rds.logical_replication') AS replicacion_logica,
       current_setting('wal_level') AS wal_level,
       current_setting('rds.force_ssl') AS ssl_obligatorio,
       (SELECT count(*) FROM tienda.clientes) AS clientes,
       (SELECT count(*) FROM tienda.productos) AS productos,
       (SELECT count(*) FROM tienda.pedidos) AS pedidos,
       (SELECT count(*) FROM tienda.items_pedido) AS items;
