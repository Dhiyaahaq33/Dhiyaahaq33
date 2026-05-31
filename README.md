## 👋 Hi, I'm Muhammad Yahya

🤖 Interested in **algorithmic trading**, **AI systems**, and **backend engineering**

📈 Currently building **crypto futures simulation** & **AI quant trading platforms**

🚀 Deploying real systems — not just notebooks

📍 From Indonesia

---

### 🛠 My Tech Stack

<p align="left">
  <img src="https://skillicons.dev/icons?i=python,fastapi,nextjs,react,vue,ts,js,html,
    tailwind,postgres,supabase,redis,docker,githubactions&theme=dark" />
</p>

---

### 📌 Featured Projects

**[QuantDingerCahyo](https://github.com/Dhiyaahaq33/QuantDingerCahyo)**
> AI quant trading platform · Backtesting · Multi-agent LLM · 10+ exchange support · Docker + Vue.js

**[ATRADEX](https://github.com/Dhiyaahaq33/ATRADEX)**
> Automated trading bot · Real-time market data · Signal execution pipeline

**[FUTURE-MARKET](https://github.com/Dhiyaahaq33/FUTURE-MARKET)**
> Futures price prediction · ML models · Feature engineering

**[AgriTwin](https://github.com/Dhiyaahaq33/AgriTwin)** 🌱
> AI greenhouse digital twin platform — production-grade evolution from 17K-line Streamlit monolith

<details>
<summary><b>📖 AgriTwin Details</b> — click to expand</summary>

<br>

**AgriTwin** is a full-stack AI-powered digital twin platform for greenhouse management, evolved from a single-file Streamlit prototype (`tumbal.py`, 15,600+ lines) into a distributed three-tier architecture through a structured 5-phase migration — with zero downtime.

#### Architecture

| Layer | Technology | Notes |
|-------|-----------|-------|
| **Frontend** | Next.js 15, React 19, Tailwind CSS | Dark-mode dashboard, mobile-responsive |
| **Backend** | FastAPI (Python), async, WebSocket | 9 REST endpoints + 1 WebSocket |
| **Database** | Supabase (PostgreSQL + Realtime) | 7 tables, dual-write with SQLite fallback |
| **IoT** | HiveMQ Cloud (MQTT TLS) | ESP32 → cloud → dashboard in <2s |
| **Weather** | Open-Meteo (free, no API key) | Current + 16-day forecast + 7-day history |
| **AI** | Gemini 2.0 Flash + RAG | 10 Indonesian agronomy documents as knowledge base |
| **Monitoring** | Sentry + PostHog | Error tracking + product analytics |
| **Deploy** | Vercel (FE) + Railway (BE) + Docker | CI/CD via GitHub Actions |

#### Key Features
- 🌡️ **Real-time IoT sensor monitoring** — temperature, humidity, CO2, soil moisture, pH, EC
- 🌦️ **Live weather integration** — Open-Meteo primary, OpenWeatherMap fallback, physics-based simulation as last resort
- 🤖 **AI Agronomist** — multi-LLM (Gemini/Groq/Ollama) with RAG context injection from local agronomy knowledge base
- 📸 **Plant Doctor** — disease detection from photos via Gemini Vision
- 🚨 **Alert Engine** — 9 threshold rules, auto-evaluation, Telegram notifications
- 💰 **Market prices** — 23 Indonesian crops, sourced from PIHPS BI / World Bank / BPS
- 🏔️ **3D terrain visualization** — real SRTM DEM from AWS Terrarium tiles + hypsometric colorscale
- 🧬 **Genetic optimizer** — NSGA-II multi-objective setpoint optimization
- 📊 **Economics engine** — full P&L, ROI, payback period, carbon credit MRV
- 🔗 **Dual-write persistence** — SQLite local + Supabase cloud (graceful degradation)

#### API Endpoints
```
GET  /api/health                → service status (Supabase, MQTT, weather)
GET  /api/weather/{lat}/{lon}   → current weather + forecast
POST /api/sensors/ingest        → receive ESP32/client sensor data
GET  /api/sensors/{zone_id}     → sensor history
GET  /api/alerts                → active alerts
POST /api/alerts/{id}/acknowledge
GET  /api/market/prices         → commodity prices (23 crops)
POST /api/ai/query              → AI agronomist (Gemini + RAG)
WS   /ws/zones/{zone_id}/live   → real-time sensor WebSocket
```

#### Migration Phases
| Phase | Scope | Status |
|-------|-------|--------|
| **0** | Security — `.env`, dotenv, Sentry, `.gitignore` | ✅ |
| **1** | Data Layer — Open-Meteo, Supabase, market prices | ✅ |
| **2** | IoT Real — HiveMQ MQTT, alert engine, ESP32 spec | ✅ |
| **3** | Backend Split — FastAPI + Next.js + Streamlit legacy | ✅ |
| **4** | Production — Docker, CI/CD, RAG, deploy configs | ✅ |

#### Tech Stack
`Python` `FastAPI` `Next.js` `React` `TypeScript` `Tailwind CSS` `PostgreSQL` `Supabase` `Redis` `MQTT` `HiveMQ` `Docker` `Sentry` `PostHog` `Gemini API` `WebSocket` `GitHub Actions`

</details>

---

*⚡ Markets are data problems. Solve them with code.*
