# pyramid scheme

yoo is this real? unfortunately not actually a pyramid scheme. this is hack club's flagship referral program! specifically the third iteration (hence the v3).
<img width="1530" height="938" alt="screengrab_noartifacts" src="https://github.com/user-attachments/assets/eeaaebfe-8d45-4b0a-9cc3-b130d62c075a" />


## ok so what do i start with 

if you love containers and want to save time [go here](#i-am-a-docker-pro-pls-dont-waste-my-time)

otherwise,

```bash
bundle install
npm install
bin/rails db:create db:migrate db:seed
```

## run

```bash
bin/dev
```

app runs on `http://localhost:4444`. ez! well you have to do some more stuff (see below) but

## test

```bash
bin/rails test
```

## env

copy `.env.example` to `.env` and configure as needed

required:
- `DATABASE_URL` - postgres connection string

everything else is optional, but add as much as you can. a lot of things might not work otherwise! make a gh issue / PR if you would like me to fix smth with the dev setup!

## so wth is qreader

qreader (this is the microservice that the reads qr codes for auto verification!):
```bash
cd qreader && PORT=4445 python main.py
```

## and worker?

background jobs (these sync data in the bg):
```bash
bin/rails solid_queue:start
```

## what about proxy?

proxy (url shortener service; you probably won't need it though!):
```bash
cd proxy && PORT=4446 python main.py
``` 

## i am a docker pro pls dont waste my time

```bash
docker-compose up
```
