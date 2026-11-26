"""The few calls this bot makes to nwn-ops-api (chapter 9). All of them work with the API's team key."""
import aiohttp


class OpsApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(f"{status}: {message}")
        self.status = status
        self.message = message


class OpsApi:
    def __init__(self, url: str, key: str, session: aiohttp.ClientSession):
        self.url = url
        self._headers = {"Authorization": f"Bearer {key}"}
        self._session = session

    async def _call(self, method: str, path: str, body: dict | None = None, timeout: float = 20) -> dict:
        try:
            async with self._session.request(method, self.url + path, json=body, headers=self._headers,
                                             timeout=aiohttp.ClientTimeout(total=timeout)) as r:
                try:
                    data = await r.json(content_type=None)
                except ValueError:
                    data = {}
                if r.status >= 400:
                    detail = data.get("detail") if isinstance(data, dict) else None
                    raise OpsApiError(r.status, str(detail or r.reason))
                return data if isinstance(data, dict) else {}
        except (aiohttp.ClientError, TimeoutError) as e:
            raise OpsApiError(0, f"the operations API did not answer ({type(e).__name__})") from e

    async def status(self) -> dict:
        return await self._call("GET", "/api/v1/server/status")

    async def progress(self) -> dict:
        """For the operations running right now (a deploy, an NWNX update); `status` has everything else."""
        return await self._call("GET", "/api/v1/server/progress?lines=1")

    async def restart(self, minutes: int, reason: str) -> dict:
        return await self._call("POST", "/api/v1/server/restart", {"wait_minutes": minutes, "reason": reason})

    async def cancel_restart(self) -> dict:
        return await self._call("POST", "/api/v1/server/cancel-restart")

    async def online(self) -> dict:
        """Who is online: {"count", "characters": [{"name"}]} (the API's ONLINE_SQL; DMs are left out there)."""
        return await self._call("GET", "/api/v1/server/online")

    async def dev_load(self, target: str, who: str) -> dict:
        """Chapter 14, tier 3: start the dev server's load workflow for pr-<n>, main or rollback (409 while one runs)."""
        return await self._call("POST", "/api/v1/dev/load", {"target": target, "requested_by": who})

    async def dev_status(self) -> dict:
        """What the dev server runs ({"loaded": {...}, "last_run": {...}})."""
        return await self._call("GET", "/api/v1/dev/status")
