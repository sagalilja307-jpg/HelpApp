class DummyMailProvider:
    def fetch_all(self):
        return []


mail_provider = DummyMailProvider()
