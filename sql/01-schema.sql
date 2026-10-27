-- One statement: compatible with one Data API ExecuteStatement request.
DO $schema$
BEGIN
    CREATE SCHEMA IF NOT EXISTS tienda;

    CREATE TABLE IF NOT EXISTS tienda.clientes (
        cliente_id integer PRIMARY KEY,
        nombre varchar(100) NOT NULL,
        ciudad varchar(80) NOT NULL,
        creado_en timestamptz NOT NULL DEFAULT current_timestamp
    );

    CREATE TABLE IF NOT EXISTS tienda.productos (
        producto_id integer PRIMARY KEY,
        nombre varchar(100) NOT NULL,
        categoria varchar(50) NOT NULL,
        precio numeric(12, 2) NOT NULL CHECK (precio >= 0),
        stock integer NOT NULL CHECK (stock >= 0)
    );

    CREATE TABLE IF NOT EXISTS tienda.pedidos (
        pedido_id integer PRIMARY KEY,
        cliente_id integer NOT NULL REFERENCES tienda.clientes (cliente_id),
        estado varchar(20) NOT NULL CHECK (estado IN ('pendiente', 'pagado', 'enviado', 'cancelado')),
        creado_en timestamptz NOT NULL,
        actualizado_en timestamptz NOT NULL DEFAULT current_timestamp
    );

    CREATE TABLE IF NOT EXISTS tienda.items_pedido (
        item_id integer PRIMARY KEY,
        pedido_id integer NOT NULL REFERENCES tienda.pedidos (pedido_id),
        producto_id integer NOT NULL REFERENCES tienda.productos (producto_id),
        cantidad integer NOT NULL CHECK (cantidad > 0),
        precio_unitario numeric(12, 2) NOT NULL CHECK (precio_unitario >= 0),
        UNIQUE (pedido_id, producto_id)
    );
END
$schema$;
