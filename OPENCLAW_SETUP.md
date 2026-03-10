# OpenClaw + NVIDIA Kimi K2.5 - Guia de Configuracion

## Problema comun
Al configurar OpenClaw con Kimi K2.5, el wizard ofrece "Moonshot AI" como provider.
Si tu API key es de **NVIDIA** (`nvapi-...`), NO funcionara con Moonshot porque son servidores diferentes.

- API key de Moonshot: empieza con `sk-...` y usa `https://api.moonshot.ai/v1`
- API key de NVIDIA: empieza con `nvapi-...` y usa `https://integrate.api.nvidia.com/v1`

Usar una key de NVIDIA contra Moonshot da: **HTTP 401: Invalid Authentication**

---

## Solucion: Configurar NVIDIA como provider

### 1. Archivo principal: `~/.openclaw/openclaw.json`

Cambiar el provider de `moonshot` a `nvidia`:

```json
{
  "auth": {
    "profiles": {
      "nvidia:default": {
        "provider": "nvidia",
        "mode": "api_key"
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "nvidia": {
        "baseUrl": "https://integrate.api.nvidia.com/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "moonshotai/kimi-k2.5",
            "name": "Kimi K2.5 (NVIDIA)",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 256000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "nvidia/moonshotai/kimi-k2.5"
      },
      "models": {
        "nvidia/moonshotai/kimi-k2.5": {
          "alias": "Kimi"
        }
      }
    }
  }
}
```

### 2. Archivo de credenciales: `~/.openclaw/agents/main/agent/auth-profiles.json`

Agregar el perfil de nvidia con tu API key:

```json
{
  "version": 1,
  "profiles": {
    "nvidia:default": {
      "type": "api_key",
      "provider": "nvidia",
      "key": "nvapi-TU_API_KEY_AQUI"
    }
  }
}
```

### 3. Modelo por agente (opcional): `~/.openclaw/agents/main/agent/models.json`

Si tambien quieres el provider a nivel de agente:

```json
{
  "providers": {
    "nvidia": {
      "baseUrl": "https://integrate.api.nvidia.com/v1",
      "api": "openai-completions",
      "models": [
        {
          "id": "moonshotai/kimi-k2.5",
          "name": "Kimi K2.5 (NVIDIA)",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 256000,
          "maxTokens": 8192
        }
      ]
    }
  }
}
```

---

## Reiniciar Gateway

Despues de cualquier cambio en la config:

```bash
# Cerrar el gateway (Ctrl+C en la terminal donde corre)
# Luego reiniciar:
openclaw gateway
```

Verificar que el log muestre:
```
[gateway] agent model: nvidia/moonshotai/kimi-k2.5
```

Si sigue mostrando `moonshot/kimi-k2.5`, revisar que `"primary"` este apuntando a `"nvidia/moonshotai/kimi-k2.5"`.

---

## Error HTTPS en dashboard remoto

Si accedes al dashboard desde otra maquina y sale:
> "control ui requires device identity (use HTTPS or localhost secure context)"

**Opcion A**: Acceder desde `http://127.0.0.1:18789` (solo si es la misma maquina)

**Opcion B**: Agregar en `openclaw.json` dentro de `gateway`:
```json
"controlUi": {
  "allowInsecureAuth": true
}
```

---

## Obtener API Key de NVIDIA

1. Ir a https://build.nvidia.com/moonshotai/kimi-k2-5
2. Click en "Generate API Key"
3. La key empieza con `nvapi-...`
