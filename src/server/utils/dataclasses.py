# You have been fooled! this file use pydantic and NOT dataclasses!
from pydantic import BaseModel


class Member(BaseModel):
    id: int
    name: str
    avatar: str
