FROM node:22-alpine

WORKDIR /app

# Les dependances d'abord : Docker garde cette couche en cache tant que
# package.json ne change pas, ce qui evite de tout reinstaller a chaque
# modification du code.
COPY package.json ./
RUN npm install --omit=dev

COPY . .

# Cree les dossiers montes en volume s'ils n'existent pas encore.
RUN mkdir -p uploads import

EXPOSE 4000
CMD ["node", "server.js"]
