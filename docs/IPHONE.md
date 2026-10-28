# Installer DocuMind sur iPhone (test sur le réseau local)

Ce guide permet d'installer l'application DocuMind sur un iPhone **sans compte
développeur Apple payant**, avec un simple identifiant Apple (Apple ID) et un
ordinateur. Il faut compter environ 20 minutes la première fois.

> **À savoir avant de commencer**
> - L'application n'est pas sur l'App Store : on l'installe soi-même avec
>   l'outil gratuit **Sideloadly**.
> - Avec un Apple ID gratuit, l'application **expire au bout de 7 jours**. Il
>   suffit alors de refaire l'étape 4 (2 minutes) : les réglages de l'app sont
>   conservés.
> - L'iPhone doit être sur **le même Wi-Fi que le serveur DocuMind**. En 4G/5G
>   ou depuis un autre réseau, l'application s'ouvre mais ne trouve pas le
>   serveur.

## Ce qu'il faut

- Un iPhone sous iOS 13 ou plus récent, et son câble USB.
- Un ordinateur Windows 10/11 ou un Mac.
- Un Apple ID (celui de l'iPhone convient). Si la validation en deux étapes
  est activée, garder l'iPhone à portée de main pour recevoir le code.
- **L'adresse du serveur DocuMind**, à demander à la personne qui l'héberge.
  Elle ressemble à `192.168.1.50:8000`.

## 1. Télécharger l'application

Ouvrir la page de la
[release v0.1.1-mobile](https://github.com/AlexandrLebegue/Documind/releases/tag/v0.1.1-mobile)
et télécharger, dans la rubrique *Assets*, le fichier
**`documind-mobile-0.1.1-unsigned.ipa`** (environ 11 Mo).
Ne pas l'ouvrir : le garder dans le dossier Téléchargements.

## 2. Préparer l'ordinateur

**Sur Windows** (sur Mac, passer directement au point 3) :

1. Installer **iTunes** et **iCloud** dans leur version téléchargée depuis le
   site d'Apple, **pas** celle du Microsoft Store : Sideloadly en a besoin pour
   dialoguer avec l'iPhone. Les liens sont donnés sur la page de Sideloadly.
2. Redémarrer l'ordinateur après l'installation.

**Sur Windows et sur Mac :**

3. Télécharger et installer **Sideloadly** depuis son site officiel :
   <https://sideloadly.io>. Ne pas utiliser d'autre site.

## 3. Brancher l'iPhone

1. Brancher l'iPhone à l'ordinateur avec le câble et le déverrouiller.
2. Si l'iPhone demande « Faire confiance à cet ordinateur ? », appuyer sur
   **Se fier** puis saisir le code de l'iPhone.

## 4. Installer DocuMind avec Sideloadly

1. Ouvrir Sideloadly. L'iPhone doit apparaître dans la liste *iDevice* en haut.
2. Glisser le fichier `documind-mobile-0.1.1-unsigned.ipa` sur la grande icône
   *IPA* à gauche (ou cliquer dessus pour le sélectionner).
3. Dans le champ *Apple account*, saisir l'adresse e-mail de l'Apple ID.
4. Cliquer sur **Start**, puis saisir le mot de passe de l'Apple ID quand il est
   demandé (et le code reçu sur l'iPhone si la validation en deux étapes est
   active). Le mot de passe est envoyé uniquement à Apple.
5. Attendre le message **Done** en bas de la fenêtre (1 à 2 minutes).
   L'icône DocuMind apparaît sur l'iPhone.

## 5. Autoriser l'application sur l'iPhone

Au premier lancement, iOS bloque l'application tant qu'on ne l'a pas autorisée.

1. **Faire confiance au développeur** : *Réglages* → *Général* →
   *VPN et gestion de l'appareil* → toucher l'adresse de l'Apple ID →
   **Faire confiance** → confirmer.
2. **Mode développeur** (iOS 16 et plus récents seulement) :
   *Réglages* → *Confidentialité et sécurité* → tout en bas,
   *Mode développeur* → activer → l'iPhone redémarre → après le redémarrage,
   confirmer **Activer**.
   Si l'option n'apparaît pas, essayer d'abord d'ouvrir DocuMind une fois,
   puis revenir dans ce menu.

## 6. Premier lancement

1. Ouvrir **DocuMind**.
2. Saisir l'adresse du serveur (par exemple `192.168.1.50:8000`), puis valider.
3. Si iOS demande l'accès au **réseau local**, répondre **Autoriser** : sans
   cela l'application ne peut pas joindre le serveur.
4. Accepter ensuite l'accès à l'**appareil photo** et aux **photos** quand il est
   demandé (utilisés pour scanner ou importer des documents).

L'adresse est mémorisée ; elle se change dans *Plus* → *Réglages* →
*Changer de serveur*.

## 7. Tous les 7 jours : renouveler l'installation

Quand DocuMind ne s'ouvre plus (message « n'est plus disponible ») :
rebrancher l'iPhone, ouvrir Sideloadly et refaire l'étape 4 avec le même
fichier `.ipa`. Les étapes 5 et 6 ne sont pas à refaire.

## En cas de problème

| Problème | Solution |
|---|---|
| L'iPhone n'apparaît pas dans Sideloadly | Débloquer l'iPhone, accepter « Se fier », changer de câble ou de port USB. Sur Windows, vérifier qu'iTunes est la version du site d'Apple. |
| Erreur de mot de passe dans Sideloadly | Vérifier l'Apple ID sur appleid.apple.com, puis réessayer. |
| « Développeur non approuvé » à l'ouverture | Refaire l'étape 5.1. |
| « Mode développeur requis » | Refaire l'étape 5.2. |
| « Serveur injoignable » | Vérifier que l'iPhone est sur le même Wi-Fi que le serveur, que l'adresse et le port sont exacts, et que l'accès au réseau local est autorisé : *Réglages* → *Confidentialité et sécurité* → *Réseau local* → DocuMind. |
| L'application s'est arrêtée de fonctionner après une semaine | Normal avec un Apple ID gratuit : voir l'étape 7. |

## Limites de cette version de test

- Version de test, non signée par Apple : à réserver à un usage personnel.
- Un Apple ID gratuit permet au plus 3 applications installées de cette façon.
- Les échanges avec le serveur passent en clair (HTTP) sur le réseau local :
  ne pas exposer le serveur sur Internet.
