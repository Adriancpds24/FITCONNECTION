FROM node:20

# FitConnect API
#
# Producción / despliegue:
# - Sirve el frontend web y la API con una URL pública (HTTPS).
# - En móvil compila con:
#   --dart-define=API_BASE_URL=https://tu-dominio.com/api
#
# Nota (solo Android por USB, local):
# - Puedes usar `adb reverse tcp:3000 tcp:3000` y luego compilar con:
#   --dart-define=API_BASE_URL=http://localhost:3000/api
#
# Variables importantes del backend:
# - DATABASE_URL
# - JWT_SECRET
# - PORT
# - SMTP_* si usas recuperacion de contrasena por email

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

RUN mkdir -p /app/uploads/posts /app/uploads/stories /app/uploads/nutrition

EXPOSE 3000

ENV NODE_ENV=production
ENV UPLOADS_DIR=/app/uploads
CMD ["npm", "start"]
