from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Message(StrictModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=3000)


class TutorRequest(StrictModel):
    requestID: UUID
    language: Literal["en", "ko"]
    level: Literal["beginner", "intermediate", "advanced"]
    scene: Literal["daily", "travel", "campus", "interview", "academic"]
    messages: list[Message] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def check_history(self):
        if sum(len(m.content) for m in self.messages) > 24000:
            raise ValueError("Conversation exceeds the supported context size")
        if any(not m.content.strip() for m in self.messages):
            raise ValueError("Empty message")
        for index, message in enumerate(self.messages):
            expected = "user" if index % 2 == 0 else "assistant"
            if message.role != expected:
                raise ValueError("Messages must alternate, starting with the learner")
        return self


class Reply(StrictModel):
    reply: str = Field(min_length=1, max_length=3000)

    @model_validator(mode="after")
    def nonempty(self):
        if not self.reply.strip():
            raise ValueError("Empty reply")
        return self


class Correction(StrictModel):
    kind: Literal["grammar", "vocabulary", "naturalness", "logic"]
    original: str = Field(min_length=1, max_length=1000)
    improved: str = Field(min_length=1, max_length=1000)
    explanation: str = Field(min_length=1, max_length=1500)


class Suggestion(StrictModel):
    term: str = Field(min_length=1, max_length=100)
    meaning: str = Field(min_length=1, max_length=500)
    example: str = Field(min_length=1, max_length=1000)


class Feedback(StrictModel):
    summary: str = Field(min_length=1, max_length=1500)
    corrections: list[Correction] = Field(max_length=8)
    suggestions: list[Suggestion] = Field(max_length=5)
    followUp: str = Field(min_length=1, max_length=1500)
