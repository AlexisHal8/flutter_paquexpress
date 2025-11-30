CREATE DATABASE IF NOT EXISTS paquexpress_db;
USE paquexpress_db;

-- Tabla de Usuarios (Agentes)
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE
);

-- Tabla de Paquetes
CREATE TABLE packages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    tracking_number VARCHAR(50) UNIQUE NOT NULL,
    destination_address TEXT NOT NULL,
    -- Coordenadas del destino (para el mapa del agente)
    dest_lat FLOAT NOT NULL,
    dest_lng FLOAT NOT NULL,
    status ENUM('pendiente', 'entregado') DEFAULT 'pendiente',
    assigned_agent_id INT,
    
    -- Campos de evidencia de entrega
    proof_photo_url VARCHAR(255),
    delivery_lat FLOAT,
    delivery_lng FLOAT,
    delivered_at DATETIME,
    
    FOREIGN KEY (assigned_agent_id) REFERENCES users(id)
);

-- Insertar un agente de prueba (Password: '123456')
-- Nota: En producción el password se inserta ya hasheado, aquí es solo ejemplo
-- El hash real lo generaremos con la API más adelante.