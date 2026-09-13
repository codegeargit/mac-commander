#!/usr/bin/env python3
"""dmg(또는 임의 파일)를 Google 공유 드라이브에 업로드하고 공유 링크를 출력한다.

서비스 계정 JSON 키로 인증한다(사람 로그인 불필요). 서비스 계정은 자체
저장공간이 없으므로 대상은 반드시 '공유 드라이브(Shared Drive)'여야 한다.

환경변수:
  GDRIVE_SA_KEY     서비스 계정 JSON 키 파일 경로(필수)
  GDRIVE_FOLDER_ID  업로드할 공유 드라이브 또는 그 안 폴더의 ID(필수)

사용:
  GDRIVE_SA_KEY=~/secrets/gcp-sa.json GDRIVE_FOLDER_ID=xxxx \
    python3 scripts/upload_to_drive.py dist/MacCommander-1.1.dmg

같은 이름의 파일이 폴더에 이미 있으면 새로 만들지 않고 내용을 갱신한다
(공유 링크가 유지되므로 배포 URL이 바뀌지 않는다).
"""
import os
import sys

try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    from googleapiclient.errors import HttpError
except ImportError:
    sys.exit(
        "필수 라이브러리가 없습니다. 설치:\n"
        "  pip install google-api-python-client google-auth"
    )

SCOPES = ["https://www.googleapis.com/auth/drive"]


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(f"사용법: {sys.argv[0]} <업로드할_파일>")
    path = os.path.expanduser(sys.argv[1])
    if not os.path.isfile(path):
        sys.exit(f"파일 없음: {path}")

    key = os.environ.get("GDRIVE_SA_KEY")
    folder = os.environ.get("GDRIVE_FOLDER_ID")
    if not key or not folder:
        sys.exit("GDRIVE_SA_KEY, GDRIVE_FOLDER_ID 환경변수가 필요합니다.")
    key = os.path.expanduser(key)
    if not os.path.isfile(key):
        sys.exit(f"서비스 계정 키 파일 없음: {key}")

    creds = service_account.Credentials.from_service_account_file(key, scopes=SCOPES)
    drive = build("drive", "v3", credentials=creds)

    name = os.path.basename(path)
    media = MediaFileUpload(path, resumable=True)
    common = {"supportsAllDrives": True}

    try:
        # 같은 폴더에 동명 파일이 있는지 확인 → 있으면 갱신, 없으면 생성.
        q = f"name = '{name}' and '{folder}' in parents and trashed = false"
        existing = drive.files().list(
            q=q, fields="files(id)",
            includeItemsFromAllDrives=True, **common,
        ).execute().get("files", [])

        if existing:
            file_id = existing[0]["id"]
            drive.files().update(fileId=file_id, media_body=media, **common).execute()
            action = "갱신"
        else:
            meta = {"name": name, "parents": [folder]}
            file_id = drive.files().create(
                body=meta, media_body=media, fields="id", **common,
            ).execute()["id"]
            action = "업로드"

        # "링크 있는 누구나 보기" 권한 부여(이미 있으면 무해).
        drive.permissions().create(
            fileId=file_id,
            body={"type": "anyone", "role": "reader"},
            **common,
        ).execute()
    except HttpError as e:
        sys.exit(f"Drive API 오류: {e}")

    link = f"https://drive.google.com/file/d/{file_id}/view"
    dl = f"https://drive.google.com/uc?export=download&id={file_id}"
    print(f"✅ Drive {action} 완료: {name}")
    print(f"   공유 링크: {link}")
    print(f"   직접 다운로드: {dl}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
