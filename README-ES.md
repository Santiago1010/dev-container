# Stack explicado para principiantes 🚀

¡Hola! 👋 Si acabas de empezar en desarrollo de software y te tocó trabajar con una pila de infraestructura, este README es para ti. Aquí te explico, de manera sencilla y con ejemplos, **qué hace cada servicio**, **cómo se conectan entre sí**, y **qué puedes esperar** cuando los uses en un proyecto real.

---

## 📚 Índice
- [Stack explicado para principiantes 🚀](#stack-explicado-para-principiantes-)
  - [📚 Índice](#-índice)
  - [1. ¿Para qué sirve esta guía? 📚](#1-para-qué-sirve-esta-guía-)
  - [2. Resumen rápido del stack ✅](#2-resumen-rápido-del-stack-)
  - [3. Descripción simple de cada servicio 🔍](#3-descripción-simple-de-cada-servicio-)
    - [🤖 Kafka](#-kafka)
    - [🚀 Redis](#-redis)
    - [🔍 Consul](#-consul)
    - [📇 Jaeger](#-jaeger)
    - [📊 Prometheus](#-prometheus)
    - [📈 Grafana](#-grafana)
    - [🚪 Kong (API Gateway)](#-kong-api-gateway)
    - [☁️ MinIO](#️-minio)
    - [🔐 Vault](#-vault)
    - [⚙️ N8N](#️-n8n)
  - [4. ¿Cómo se integran entre sí? - Flujos comunes 🔗](#4-cómo-se-integran-entre-sí---flujos-comunes-)
    - [🔄 Flujo A: Subida de archivo por usuario (ej. avatar)](#-flujo-a-subida-de-archivo-por-usuario-ej-avatar)
    - [🔐 Flujo B: Login y sesión](#-flujo-b-login-y-sesión)
    - [🔎 Flujo C: Microservicio descubriendo otro (Consul)](#-flujo-c-microservicio-descubriendo-otro-consul)
    - [🤖 Flujo D: Automatización con N8N para Mensajería](#-flujo-d-automatización-con-n8n-para-mensajería)
  - [5. Checklist de implementación por prioridad 🧭](#5-checklist-de-implementación-por-prioridad-)
  - [6. Buenas prácticas y recomendaciones de seguridad 🔒](#6-buenas-prácticas-y-recomendaciones-de-seguridad-)
  - [7. Glosario de términos para principiantes 🧠](#7-glosario-de-términos-para-principiantes-)
  - [8. Troubleshooting rápido 🛠️](#8-troubleshooting-rápido-️)
  - [9. ¿Qué sigue? Ideas para practicar ✨](#9-qué-sigue-ideas-para-practicar-)

---

## 1. ¿Para qué sirve esta guía? 📚

Para que entiendas, paso a paso y con lenguaje simple, los servicios que suelen aparecer en proyectos modernos: mensajería, cache, observabilidad, gestión de secretos, almacenamiento de objetos y automatización. Todo explicado como si te lo contara un compañero con paciencia.

---

## 2. Resumen rápido del stack ✅

*   **Kafka** — mensajería / eventos
*   **Redis** — caché y estructuras rápidas en memoria
*   **Consul** — descubrimiento de servicios y checks de salud
*   **Jaeger** — trazado distribuido (tracing)
*   **Prometheus** — recolección de métricas
*   **Grafana** — dashboards para ver las métricas
*   **Kong** — API Gateway (punto de entrada a tus APIs)
*   **MinIO** — almacenamiento de archivos (compatible con S3)
*   **Vault** — gestión segura de secretos
*   **N8N** — automatización / orquestación low-code

---

## 3. Descripción simple de cada servicio 🔍

> Para cada servicio verás: **Qué es**, **Para qué sirve**, **Ejemplo sencillo**, y **¿Por qué usarlo en microservicios vs monolito?**

### 🤖 Kafka
*   **Qué es:** Un sistema para enviar y almacenar eventos/mensajes de manera rápida, duradera y en orden.
*   **Para qué sirve:** Comunicar partes de tu sistema sin que estén acopladas (producer → topic → consumer). Es ideal para procesar streams de datos.
*   **Ejemplo sencillo:** Cuando un usuario sube una foto, el servicio que recibe la foto publica un evento "foto_subida" en Kafka; otro servicio (thumbnailer) lee ese evento y crea miniaturas. 
*   **Microservicios:** Ideal. Permite desacoplar, procesar eventos en paralelo y volver a reproducir eventos si es necesario.
*   **Monolito:** Útil para pipelines (analítica), pero puede ser demasiado complejo si tu app es pequeña.

**💡 Ejemplo de Integración con WebSockets:**
Puedes usar Kafka como cola de mensajes para un chat en tiempo real. Cuando un usuario envía un mensaje, un WebSocket lo publica en un tema de Kafka. Otro servicio consume esos mensajes y los difunde a todos los clientes conectados via WebSocket. Esto te permite escalar los componentes de conexión y procesamiento de mensajes por separado.

**🔧 Ejemplos de código:**
*Node.js (Producer):*
```javascript
const { Kafka } = require('kafkajs');
const kafka = new Kafka({ clientId: 'my-app', brokers: ['kafka:9092'] });
const producer = kafka.producer();
await producer.connect();
await producer.send({ topic: 'test-topic', messages: [ { key: 'key1', value: 'Hello Kafka!' } ], });
await producer.disconnect();
```
*Go (Consumer):*
```go
package main
import ("github.com/segmentio/kafka-go")
func main() {
    r := kafka.NewReader(kafka.ReaderConfig{ Brokers: []string{"kafka:9092"}, Topic: "test-topic", GroupID: "my-group" })
    for { m, _ := r.ReadMessage(); fmt.Printf("Message: %s\n", string(m.Value)) }
    r.Close()
}
```

### 🚀 Redis
*   **Qué es:** Base de datos en memoria, super rápida.
*   **Para qué sirve:** Caché, contadores, sesiones, pub/sub ligero, leaderboards para juegos.
*   **Ejemplo sencillo:** Cacheas la respuesta de una consulta a la DB durante 60 segundos para evitar repetir la consulta.
*   **Microservicios:** Muy útil para caches compartidas, locks distribuidos y rate limiting.
*   **Monolito:** Útil igualmente para caching y sesiones.

**💡 Ejemplo de Gamificación:**
Puedes usar las estructuras de datos de Redis (como **Sorted Sets**) para implementar un sistema de líderboards en una aplicación con elementos de gamificación. Cada vez que un usuario gana puntos, actualizas su puntuación en el sorted set. Redis mantiene el orden automáticamente, haciendo muy eficiente obtener el top 10 de usuarios.

**🔧 Ejemplos de código:**
*PHP (Caché):*
```php
<?php
$redis = new Redis();
$redis->connect('127.0.0.1', 6379);
$key = 'homepage_feed';
if (!$redis->exists($key)) { 
    $data = get_expensive_feed_from_database(); 
    $redis->setex($key, 60, json_encode($data)); 
} else { 
    $data = json_decode($redis->get($key)); 
}
?>
```
*Rust:*
```rust
use redis::Commands;
fn main() -> redis::RedisResult<()> {
    let client = redis::Client::open("redis://127.0.0.1/")?;
    let mut con = client.get_connection()?;
    let _: () = con.set("my_key", "My cached value")?;
    let value: String = con.get("my_key")?;
    println!("Value from Redis: {}", value);
    Ok(())
}
```

### 🔍 Consul
*   **Qué es:** Registro y descubrimiento de servicios + health checks.
*   **Para qué sirve:** Permite a los servicios encontrarse entre sí sin IPs fijas en ambientes dinámicos.
*   **Ejemplo sencillo:** El servicio A registra su IP/puerto; el servicio B pide a Consul "¿dónde está A?" y Consul responde.
*   **Microservicios:** Muy útil para ambientes dinámicos donde las IPs cambian.
*   **Monolito:** Normalmente no necesario si todo se despliega junto.

### 📇 Jaeger
*   **Qué es:** Herramienta para seguir la ruta de una petición entre servicios (tracing distribuido).
*   **Para qué sirve:** Detectar qué servicio está lento o falla en una operación distribuida.
*   **Ejemplo sencillo:** Al procesar un pedido, Jaeger te muestra que la mayor latencia está en la llamada al servicio de pagos.
*   **Microservicios:** Casi imprescindible para depurar latencias.
*   **Monolito:** Útil para perfilar internamente pero de menor prioridad.

### 📊 Prometheus
*   **Qué es:** Sistema para recolectar métricas (números) de tus servicios.
*   **Para qué sirve:** Medir uso de CPU, memoria, peticiones por segundo, errores, etc.
*   **Ejemplo sencillo:** Monitorizas la cantidad de requests por minuto y alertas si sube mucho.
*   **Microservicios:** Cada servicio expone métricas; Prometheus las scrapea y centraliza.
*   **Monolito:** Igualmente útil para ver comportamiento y alertas.

### 📈 Grafana
*   **Qué es:** Herramienta para crear dashboards bonitos con tus métricas. 
*   **Para qué sirve:** Visualizar tendencias, montar paneles para SRE o producto.
*   **Ejemplo sencillo:** Dashboard con latencia promedio, errores 5xx, y número de usuarios activos.
*   **Microservicios y monolito:** Útil en ambos casos.

### 🚪 Kong (API Gateway)
*   **Qué es:** Punto único de entrada para tus APIs. Maneja autenticación, rate-limiting, logging.
*   **Para qué sirve:** Centralizar política de seguridad y enrutamiento.
*   **Ejemplo sencillo:** Todas las llamadas externas llegan primero a Kong; Kong valida el JWT y forwardea al servicio correspondiente.
*   **Microservicios:** Muy útil para aplicar reglas transversales sin tocar cada microservicio.
*   **Monolito:** Útil para exponer versiones públicas y gestionar SSL, aunque a veces un reverse proxy simple basta.

**💡 Ejemplo para Notificaciones Push:**
Kong puede actuar como un único punto de entrada para una API que gestiona notificaciones push. Puedes configurar un plugin de rate-limiting en Kong para evitar que un solo cliente envíe demasiadas notificaciones. También puede manejar la autenticación para los servicios de envío de SMS (Twilio) o Email (SendGrid, Mailgun).

### ☁️ MinIO
*   **Qué es:** Almacenamiento de objetos (archivos) compatible con S3.
*   **Para qué sirve:** Guardar fotos, documentos, backups, videos.
*   **Ejemplo sencillo:** El servicio de uploads guarda en MinIO; otro servicio lee desde MinIO para mostrar imágenes. 
*   **Microservicios:** Muy útil para centralizar archivos compartidos.
*   **Monolito:** Útil para manejar uploads internos sin depender de la nube.

**🔧 Ejemplos de código:**
*.NET (C#):*
```csharp
using Minio;
var minio = new MinioClient()
    .WithEndpoint("play.min.io")
    .WithCredentials("Q3AM3UQ867SPQQA43P2F", "zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG")
    .Build();
try
{
    var args = new PutObjectArgs()
        .WithBucket("my-bucket")
        .WithObject("photo.jpg")
        .WithFileName("local-photo.jpg");
    await minio.PutObjectAsync(args);
}
catch (Exception e) { Console.WriteLine(e); }
```
*Go:*
```go
package main
import ("github.com/minio/minio-go/v7") 
func main() {
    minioClient, err := minio.New("play.min.io", &minio.Options{Creds: credentials.NewStaticV4("Q3AM3UQ867SPQQA43P2F", "zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG", "")})
    if err != nil { panic(err) }
    info, err := minioClient.FPutObject(ctx, "my-bucket", "photo.jpg", "local-photo.jpg", minio.PutObjectOptions{})
}
```

### 🔐 Vault
*   **Qué es:** Almacén seguro para secretos (claves, contraseñas, certificados). 
*   **Para qué sirve:** Evitar poner contraseñas en código o repositorios. Puede generar credenciales bajo demanda y rotarlas automáticamente.
*   **Ejemplo sencillo:** Tus servicios piden credenciales a Vault en tiempo de ejecución y Vault entrega credenciales rotadas.
*   **Microservicios:** Crítico para seguridad; gestionar accesos por servicio.
*   **Monolito:** Recomendado para no hardcodear secretos.

**💡 Integración con Asistentes de IA:**
Puedes usar Vault para gestionar de forma segura las API Keys de servicios como OpenAI, DeepSeek o Gemini. Tu aplicación o bot (ej. un bot de Discord) solicita la clave a Vault cuando necesita hacer una petición, en lugar de tenerla hardcodeada en el código o en variables de entorno en texto plano. Vault puede incluso rotar estas claves si la API lo permite.

**🔧 Ejemplos de código:**
*Node.js:*
```javascript
const vault = require("node-vault")({ apiVersion: 'v1', endpoint: 'http://127.0.0.1:8200' });
const roleId = process.env.APPROLE_ROLE_ID;
const secretId = process.env.APPROLE_SECRET_ID;
const auth = await vault.approleLogin({ role_id: roleId, secret_id: secretId });
vault.token = auth.auth.client_token;
const { data } = await vault.read('secret/data/myapp');
console.log(`My DB pass is: ${data.data.db_password}`);
```

### ⚙️ N8N
*   **Qué es:** Herramienta para automatizar tareas (arrastrar y conectar nodos).
*   **Para qué sirve:** Orquestar integraciones sin escribir microservicios para todo.
*   **Ejemplo sencillo:** Cuando se crea un nuevo usuario, N8N envía un correo, añade el usuario a un CRM y sube un registro a Google Sheets.
*   **Microservicios:** Bueno como orquestador para integraciones con servicios externos.
*   **Monolito:** Útil para tareas operativas que no quieres codificar en la app principal.

**💡 Casos de Uso Avanzados:**
*   **Mensajería (WhatsApp/Telegram):** Configura un webhook en N8N que se active cuando recibe un mensaje de Twilio (para WhatsApp) o de la API de Telegram. Luego, según el contenido del mensaje, N8N puede consultar una base de datos, llamar a una API de IA para generar una respuesta inteligente, y enviar la respuesta de vuelta al usuario.
*   **Bots de Discord:** Un comando en Discord puede llegar a N8N via webhook. N8N puede procesarlo, por ejemplo, pidiendo a la API de OpenAI que genere una imagen (DALL-E) o un texto, y luego enviar el resultado de vuelta al canal de Discord.

---

## 4. ¿Cómo se integran entre sí? - Flujos comunes 🔗

A continuación verás varios *flujos* con pasos sencillos que muestran cómo los servicios pueden trabajar juntos. Piensa en estos como recetas.

### 🔄 Flujo A: Subida de archivo por usuario (ej. avatar)
1.  El cliente (web/mobile) hace una llamada al **Gateway (Kong)**.
2.  Kong valida el token (autenticación) y forwardea al servicio de uploads.
3.  El **servicio de uploads** guarda el archivo en **MinIO** y devuelve la URL.
4.  El servicio publica un evento `archivo_subido` en **Kafka** para que otros servicios reaccionen (ej. generar miniaturas, indexar en search).
5.  Un worker suscrito a `archivo_subido` procesa la imagen y guarda resultados en la DB; almacena caches en **Redis** si es necesario (p. ej. URLs pre-rendered).
6.  El servicio registra métricas (requests, duración) que **Prometheus** scrapea; las visualizas en **Grafana**.
7.  Los spans de la petición (HTTP, DB, llamadas internas) aparecen en **Jaeger** para rastrear latencias.

### 🔐 Flujo B: Login y sesión
1.  El usuario llama a Kong con sus credenciales.
2.  Kong envía la petición al servicio de autenticación.
3.  El servicio consulta **Vault** para obtener la clave privada/secretos necesarios y valida credenciales.
4.  Si todo ok, el servicio guarda la sesión en **Redis** (o emite JWT) y publica un evento `usuario_logueado` en **Kafka** para métricas o acciones posteriores.
5.  Prometheus recoge métricas de latencia y errores; Grafana muestra dashboards.

### 🔎 Flujo C: Microservicio descubriendo otro (Consul)
1.  Microservicio A quiere llamar a B, pero no conoce su IP.
2.  A pregunta a **Consul**: "¿dónde está B?". Consul responde con la IP de una instancia saludable de B.
3.  A llama a B directamente y Jaeger registra el trace.

### 🤖 Flujo D: Automatización con N8N para Mensajería
1.  Un usuario envía un comando "/imagen un gato con sombrero" a tu **Bot de Telegram**.
2.  Telegram envía un webhook a un endpoint configurado en **N8N**.
3.  **N8N** recibe el webhook, extrae el comando y el texto.
4.  N8N llama a la **API de OpenAI (DALL-E)** para generar la imagen, obteniendo la API Key de **Vault**.
5.  N8N recibe la URL de la imagen generada y la sube a **MinIO** para alojamiento persistente.
6.  N8N envía la imagen (o su URL) de vuelta al usuario de Telegram a través de la API de Bot de Telegram.

---

## 5. Checklist de implementación por prioridad 🧭

**Fase 0 — MVP pequeño (comienzas desde cero)**
*   [ ] Kong o un reverse-proxy simple (exponer APIs seguro).
*   [ ] MinIO para uploads locales (si necesitas archivos).
*   [ ] Redis para cache/sesiones (mejora rendimiento rápido).

**Fase 1 — Observabilidad básica**
*   [ ] Prometheus (a métricas básicas: requests, errores, latencias).
*   [ ] Grafana (1 dashboard con: tráfico, errores, latencia).

**Fase 2 — Escalado y comunicación**
*   [ ] Kafka (cuando necesites procesar eventos en background o desacoplar servicios).
*   [ ] Jaeger (si empiezas a tener varias llamadas entre servicios).

**Fase 3 — Seguridad y operaciones**
*   [ ] Vault (gestión de secretos).
*   [ ] Consul (si no usas Kubernetes y necesitas discovery).
*   [ ] N8N (automatizaciones operativas).

---

## 6. Buenas prácticas y recomendaciones de seguridad 🔒

*   **Nunca** guardes secretos en código o repositorios. Usa Vault. 
*   Protección de UIs: Redis Commander, Konga, Kafka UI no deben estar públicas sin autenticación.
*   TLS siempre para tráfico externo (Kong puede manejar TLS termination).
*   Controla la cardinalidad en Prometheus (evita demasiadas etiquetas dinámicas).
*   Sampling en Jaeger: no traces al 100% si no tienes capacidad de almacenamiento.
*   Respaldos para MinIO y configuraciones de Kafka (no pierdas datos). 

---

## 7. Glosario de términos para principiantes 🧠

*   **Broker:** Servidor que recibe y entrega mensajes (Kafka es un broker). 
*   **Topic:** Canal/tema donde se publican mensajes en un sistema de mensajería como Kafka.
*   **Cache:** Almacenamiento temporal para respuestas rápidas (Redis).
*   **Tracing / Trace / Span:** Seguimiento de una petición paso a paso (Jaeger). Un "trace" es el camino completo, y un "span" representa una única operación dentro de ese camino.
*   **Metric / Scrape:** Número medido (requests/sec); Prometheus "scrapea" endpoints para recogerlas.
*   **API Gateway:** Puerta de entrada para las APIs; gestiona auth, límites y logging (Kong).
*   **Object Storage / Bucket:** Lugar para guardar archivos como objetos, en lugar de en una jerarquía de archivos (MinIO, S3). 
*   **Secrets:** Credenciales / claves que debes proteger (Vault). 
*   **Webhook:** Una URL que acepta peticiones HTTP (normalmente POST) de un servicio externo para notificar sobre un evento.
*   **Pub/Sub (Publicar/Suscribir):** Patrón de mensajería donde los "emisores" (publishers) envían mensajes a un "topic" sin saber qué "receptores" (subscribers) los recibirán.

---

## 8. Troubleshooting rápido 🛠️

*   **Problema:** "No llegan mensajes a mi consumidor Kafka" → Revisa offsets, consumer group y que el topic esté activo.
*   **Problema:** "La cache no se invalida" → Verifica TTL y políticas de invalidación. Asegura que la clave usada para guardar/leer sea la misma.
*   **Problema:** "Mi servicio no encuentra a otro" → Verifica registro y health checks en Consul o la configuración de discovery.
*   **Problema:** "No veo traces en Jaeger" → Asegúrate de propagar headers de trace en llamadas HTTP y que el sampler esté activado.
*   **Problema:** "Prometheus no scrapea mi servicio" → Confirma que el endpoint de métricas esté expuesto y accesible desde Prometheus.

---

## 9. ¿Qué sigue? Ideas para practicar ✨

*   **Proyecto 1:** Implementa el flujo de subida de archivos: cliente → Kong → servicio → MinIO → Kafka → worker.
*   **Proyecto 2:** Expón métricas básicas en tu servicio (usando las librerías de Prometheus para tu lenguaje) y crea un dashboard en Grafana.
*   **Proyecto 3:** Crea un workflow simple en N8N: cuando llega un evento por webhook (puedes simularlo con `curl`), envía un email o un mensaje a un canal de Slack/Telegram.
*   **Proyecto 4:** Juega con Vault: guárdale un secreto (como una clave de API ficticia) y recupéralo desde un pequeño script en Node.js o Go.
*   **Proyecto 5 (Avanzado):** Construye un bot simple para Discord o Telegram que use N8N para recibir comandos y, por ejemplo, consulte una API pública y responda.