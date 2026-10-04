import uuid

from fastapi import APIRouter, HTTPException, Response, status

from app.api.deps import CurrentUser, Social
from app.services.social_service import CommentMissingError, NotCommentOwnerError

router = APIRouter(prefix="/comments", tags=["comments"])


@router.delete("/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_comment(comment_id: uuid.UUID, user: CurrentUser, social: Social) -> Response:
    """Authors can delete their own comments."""
    try:
        social.delete_comment(user, comment_id)
    except CommentMissingError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Comment not found") from None
    except NotCommentOwnerError:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "You can only delete your own comments"
        ) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)
