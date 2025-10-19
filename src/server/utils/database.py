from uuid import UUID, uuid4
from typing import final
from os import environ
from datetime import datetime, time, date
from sqlmodel import (
    SQLModel,
    Relationship,
    Field,
    UniqueConstraint,
    create_engine,
    Session,
    select,
)
from sqlalchemy import Column, BigInteger
from dotenv import load_dotenv

_ = load_dotenv()


class UserPollLink(SQLModel, table=True):
    id: UUID = Field(default_factory=uuid4, primary_key=True)
    user_id: int = Field(foreign_key="user.id")
    poll_id: UUID = Field(foreign_key="poll.id")

    __table_args__ = (UniqueConstraint("user_id", "poll_id"),)

    available_times: list["AvailableTimes"] = Relationship(cascade_delete=True)


class AvailableTimes(SQLModel, table=True):
    link_id: UUID = Field(foreign_key="userpolllink.id", primary_key=True)
    time_available: datetime = Field(primary_key=True)

    link: UserPollLink = Relationship(back_populates="available_times")


class User(SQLModel, table=True):
    id: int = Field(sa_column=Column(BigInteger, primary_key=True))
    created_polls: list["Poll"] = Relationship(
        back_populates="creator", cascade_delete=True
    )
    polls: list["Poll"] = Relationship(
        back_populates="users", link_model=UserPollLink, cascade_delete=True
    )


class Poll(SQLModel, table=True):
    id: UUID = Field(default_factory=uuid4, primary_key=True)
    name: str
    creator_id: int = Field(foreign_key="user.id")
    creation_time: datetime
    start_time: time
    end_time: time
    start_date: date
    end_date: date
    creator: User = Relationship(back_populates="created_polls")
    users: list[User] = Relationship(
        back_populates="polls", link_model=UserPollLink, cascade_delete=True
    )


@final
class Database:
    def __init__(self):
        self._engine = create_engine(environ["DATABASE_URL"], echo=True)
        SQLModel.metadata.create_all(self._engine)

    def create_user(self, user_id: int):
        with Session(self._engine) as session:
            session.add(User(id=user_id))

            session.commit()

    def create_poll(
        self,
        name: str,
        creator_id: int,
        start_time: time,
        end_time: time,
        start_date: date,
        end_date: date,
    ):
        with Session(self._engine) as session:
            session.add(
                Poll(
                    name=name,
                    creator_id=creator_id,
                    creation_time=datetime.now(),
                    start_time=start_time,
                    end_time=end_time,
                    start_date=start_date,
                    end_date=end_date,
                )
            )

            session.commit()

    def create_user_poll_connection(self, user_id: int, poll_id: UUID):
        with Session(self._engine) as session:
            session.add(UserPollLink(user_id=user_id, poll_id=poll_id))

            session.commit()

    def create_user_poll_available_times(
        self, poll_id: UUID, user_id: int, available_times: list[datetime]
    ):
        with Session(self._engine) as session:
            link_query = (
                select(UserPollLink)
                .where(UserPollLink.user_id == user_id)
                .where(UserPollLink.poll_id == poll_id)
                .limit(1)
            )

            result = session.exec(link_query)
            link = result.first()

            if not link:
                return False

            for new_time in available_times:
                session.add(AvailableTimes(link_id=link.id, time_available=new_time))

            session.commit()
