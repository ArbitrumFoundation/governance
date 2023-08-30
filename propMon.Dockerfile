# Dockerfile
FROM node:16

WORKDIR /app

COPY package.json ./
COPY yarn.lock ./

RUN yarn install

COPY . .

RUN git submodule update --init --recursive 

RUN yarn build

CMD ["yarn", "propmon"]