# TAK Server 5.4 for Unraid

A complete, automated setup for TAK Server 5.4 on Unraid with proper JKS certificate generation and network binding fixes.

## 🚀 Features

- ✅ **Automated JKS certificate generation** using OpenJDK container
- ✅ **Proper network binding configuration** (host="0.0.0.0")
- ✅ **Custom port mappings** to avoid conflicts
- ✅ **TAK-compliant password generation** (15+ chars with requirements)
- ✅ **Complete Unraid compatibility** (no dpkg dependencies)
- ✅ **One-script installation** with error checking

## 📋 Requirements

- **Unraid:** 6.9+ with Docker support
- **RAM:** 4GB minimum (8GB+ recommended)
- **Storage:** 2GB+ free space
- **Network:** Available ports for custom mappings
- **TAK Server 5.4 ZIP** from https://tak.gov/products/tak-server

## 🚀 Quick Start

### Method 1: Direct Installation

### Method 2: Community Applications (Coming Soon)
Install directly from Unraid Community Applications store.

## 🌐 Port Mappings

| Service | External Port | Internal Port | Description |
|---------|---------------|---------------|-------------|
| Web Interface | **8445** | 8443 | Admin dashboard |
| API | **8446** | 8444 | TAK Server API |
| Streaming | **8447** | 8446 | Data streaming |
| Client Connections | **8092** | 8089 | ATAK clients |
| Federation | **9003** | 9000 | Server federation |
| Ignite | **9004** | 9001 | Ignite service |

## 🔐 Access Your TAK Server

After successful installation:

1. **Save the generated passwords** (displayed only once)
2. **Download admin certificate:** `tak/certs/files/admin.p12`
3. **Import certificate** to your browser (password: `atakatak`)
4. **Access web interface:** `https://YOUR-UNRAID-IP:8445`

## 📱 ATAK Mobile Setup

Use the generated user certificate package:
- **File:** `tak/certs/files/user1.zip`
- **Connection:** `YOUR-UNRAID-IP:8092`

## 🆚 What Makes This Different

This solution resolves critical TAK Server 5.4 compatibility issues:

- **JKS Certificate Requirement:** TAK 5.4 requires Java KeyStore format
- **Network Binding Issues:** Must bind to 0.0.0.0 for Docker access
- **Unraid Compatibility:** No Debian dependencies (dpkg, etc.)
- **Password Complexity:** TAK 5.4 enforces strict password requirements

## 📖 Documentation

- **[Installation Guide](docs/installation.md)** - Detailed setup instructions
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## 🤝 Support

- **GitHub Issues:** [Report bugs or request features](https://github.com/Zeroradiance/tak-server-unraid/issues)
- **Unraid Forum:** [Community discussion thread](https://forums.unraid.net/topic/XXXXX-tak-server-54-for-unraid/)

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Cloud-RF** for the original TAK Server Docker wrapper
- **TAK.gov** for TAK Server
- **Unraid Community** for testing and feedback

---

**⭐ If this helped you, please star the repository!**
