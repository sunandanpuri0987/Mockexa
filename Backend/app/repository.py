"""Supabase PostgREST persistence. Every request carries the caller's JWT so RLS applies."""
from __future__ import annotations
from typing import Any
import httpx
from app.config import get_settings

class RepositoryError(Exception): pass
class NotFoundError(RepositoryError): pass

class SupabaseRepository:
    def __init__(self, url: str | None = None, anon_key: str | None = None, transport: httpx.AsyncBaseTransport | None = None):
        settings = get_settings()
        self.url = (url or settings.supabase_url or "").rstrip("/")
        self.anon_key = anon_key or settings.supabase_anon_key
        self.transport = transport
    def _headers(self, token: str, prefer: str | None = None) -> dict[str, str]:
        if not self.url or not self.anon_key: raise RepositoryError("Supabase persistence is not configured")
        headers={"apikey":self.anon_key,"Authorization":f"Bearer {token}","Content-Type":"application/json"}
        if prefer: headers["Prefer"]=prefer
        return headers
    async def _request(self, method: str, table: str, token: str, *, params: dict[str,str] | None=None, data: Any=None, prefer: str | None=None) -> Any:
        try:
            async with httpx.AsyncClient(base_url=f"{self.url}/rest/v1", transport=self.transport, timeout=15) as client:
                response=await client.request(method, f"/{table}", headers=self._headers(token,prefer), params=params, json=data)
        except httpx.HTTPError as exc:
            raise RepositoryError("Supabase persistence is unreachable") from exc
        if response.status_code == 404: raise NotFoundError(table)
        if response.status_code >= 400: raise RepositoryError(f"Supabase {table} request failed ({response.status_code}): {response.text}")
        if not response.content: return None
        return response.json()
    async def ensure_profile(self, user_id: str, token: str) -> dict:
        rows=await self._request("POST","profiles",token,data={"id":user_id},prefer="resolution=merge-duplicates,return=representation")
        return rows[0]
    async def profile(self,user_id:str,token:str)->dict:
        rows=await self._request("GET","profiles",token,params={"id":f"eq.{user_id}","select":"*"})
        if not rows: raise NotFoundError("profile")
        return rows[0]
    async def update_profile(self,user_id:str,token:str,data:dict)->dict:
        rows=await self._request("PATCH","profiles",token,params={"id":f"eq.{user_id}"},data=data,prefer="return=representation")
        if not rows: raise NotFoundError("profile")
        return rows[0]
    async def questions(self, kind:str, domains:list[str], token:str)->list[dict]:
        # Domains are validated enum-like values; PostgREST's `in` filter is safe after that validation.
        domain_filter="in.("+",".join(domains)+")"
        return await self._request("GET","questions",token,params={"kind":f"eq.{kind}","domain":domain_filter,"active":"eq.true","select":"*","order":"difficulty.asc"})
    async def create_session(self,data:dict,token:str)->dict:
        rows=await self._request("POST","sessions",token,data=data,prefer="return=representation")
        return rows[0]
    async def session(self,session_id:str,user_id:str,token:str)->dict:
        rows=await self._request("GET","sessions",token,params={"id":f"eq.{session_id}","user_id":f"eq.{user_id}","select":"*"})
        if not rows: raise NotFoundError("session")
        return rows[0]
    async def update_session(self,session_id:str,user_id:str,token:str,data:dict)->dict:
        rows=await self._request("PATCH","sessions",token,params={"id":f"eq.{session_id}","user_id":f"eq.{user_id}"},data=data,prefer="return=representation")
        if not rows: raise NotFoundError("session")
        return rows[0]
    async def add_answer(self,data:dict,token:str)->dict:
        rows=await self._request("POST","answers",token,data=data,params={"on_conflict":"session_id,question_id"},prefer="resolution=merge-duplicates,return=representation")
        return rows[0] if rows else {}
    async def answers(self,session_id:str,token:str)->list[dict]:
        return await self._request("GET","answers",token,params={"session_id":f"eq.{session_id}","select":"*,questions(prompt,ideal_answer,domain)","order":"created_at.asc"})
    async def add_message(self,data:dict,token:str)->dict:
        rows=await self._request("POST","gd_messages",token,data=data,prefer="return=representation")
        return rows[0]
    async def messages(self,session_id:str,token:str)->list[dict]:
        return await self._request("GET","gd_messages",token,params={"session_id":f"eq.{session_id}","select":"*","order":"turn_index.asc,created_at.asc"})
    async def upsert_feedback(self,data:dict,token:str)->dict:
        rows=await self._request("POST","feedback",token,data=data,prefer="resolution=merge-duplicates,return=representation")
        return rows[0]
    async def feedback(self,session_id:str,token:str)->dict | None:
        rows=await self._request("GET","feedback",token,params={"session_id":f"eq.{session_id}","select":"*"})
        return rows[0] if rows else None
    async def sessions(self,user_id:str,token:str)->list[dict]:
        return await self._request("GET","sessions",token,params={"user_id":f"eq.{user_id}","select":"*","order":"started_at.desc"})
