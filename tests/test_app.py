from app import create_app


def test_index_page():
    app = create_app()
    app.testing = True
    client = app.test_client()

    resp = client.get("/")
    assert resp.status_code == 200
