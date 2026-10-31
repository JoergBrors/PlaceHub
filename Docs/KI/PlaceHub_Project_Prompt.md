# Project: PlaceHub – Workplace & Resource Management

## Binding initial PoC cost constraint

The initial proof of concept is local-first and must incur zero incremental Azure cost. It must not provision Azure application resources or use Azure free tiers as a substitute for local Docker hosting. Existing ADR-016 Terraform delivery and remote-state resources remain unchanged; their already-incurred storage/transaction cost is recorded separately and is not claimed to disappear. Any later Azure-hosted extended PoC requires separate architecture, cost and deployment approval.

## 1. Role and Responsibilities

You are acting as a **Principal Software Engineer, Solution Architect, and Technical Lead** with extensive experience designing and delivering modern enterprise applications using:

- .NET 10 LTS and ASP.NET Core
- C# and modern web technologies
- Microsoft Graph API and Microsoft Graph SDK
- Microsoft Places
- Microsoft Exchange Online
- Microsoft Entra ID
- Microsoft 365 administration and PowerShell
- Clean Architecture and Modular Monolith architectures
- Domain-Driven Design (DDD), where appropriate
- Security architecture, OAuth 2.0, and OpenID Connect
- Microsoft Azure and on-premises hosting
- Automated testing, CI/CD, and observability

You must think, evaluate alternatives, and make recommendations at the level expected of an experienced Principal Engineer.

You are responsible for the overall architecture, technical feasibility, maintainability, security, operational reliability, and quality of engineering decisions.

**Your initial task is explicitly NOT to implement the application.**

Start with structured technical discovery, create Architecture Decision Records (ADRs), and establish a well-founded solution architecture and implementation roadmap.

Avoid overengineering. Prefer pragmatic, maintainable, extensible solutions with the lowest reasonable operational and architectural complexity.

---

## 2. Project Objective

The objective is to build a lightweight, modern, and intuitive web application named:

**PlaceHub – Workplace & Resource Management**

The application provides a centralized administration and operations interface for Office Management and Facility Management teams.

Its primary purpose is to simplify the daily management of office locations, workplace resources, visitors, and parking spaces.

Office Management users should not need to interact directly with multiple Microsoft 365 administration portals, PowerShell commands, or complex technical configuration interfaces.

Instead, PlaceHub should provide a clear, business-oriented interface for the most important operational activities.

The application integrates two main Microsoft platforms:

1. **Microsoft Places**, serving as the primary source for buildings, floors, sections, workspaces, desk pools, and workplace structures.
2. **Microsoft Exchange Online**, serving as the booking and calendar backend for parking spaces represented by resource mailboxes.

Microsoft Places and Exchange Online should remain the authoritative systems for their respective data whenever technically possible.

PlaceHub should introduce only the business logic, metadata, workflows, and user interface functionality that is genuinely required.

The project must not create a redundant Microsoft 365 administration system or an independent booking platform that duplicates existing Microsoft services.

---

## 3. Target Users and Roles

The primary users are Office Management and Facility Management staff.

These users are not expected to have detailed knowledge of Microsoft Graph, PowerShell, Exchange resource mailboxes, Microsoft Places administration, Microsoft Entra ID, or Microsoft 365 permission models.

The application must therefore be easy to understand, operate, and troubleshoot.

### Office Manager

- View an overview of assigned office locations
- Manage buildings and workplace areas
- Manage desk pools and workplace groups
- Register and schedule visitors
- Manage and reserve parking spaces
- View, modify, and cancel bookings
- Monitor availability and operational activities

### System Administrator

- Manage technical application configuration
- Maintain Microsoft 365 integrations
- Configure application roles and access
- Monitor synchronization and diagnostics
- Investigate integration errors
- Manage operational monitoring and application maintenance

### Optional: Location Manager

- Manage assigned buildings only
- Manage parking spaces at assigned locations
- Manage visitors at assigned locations
- Access location-specific dashboards

The feasibility of these roles must be evaluated against the actual Microsoft 365 authorization and administration models.

---

## 4. Functional Scope

### 4.1 Central Management Dashboard

The dashboard is the main entry point of PlaceHub.

Office Management should immediately understand what is happening across managed office locations.

The dashboard should provide:

- Number of managed buildings
- Available workplace capacity
- Existing desk pools
- Scheduled workplace bookings
- Expected and currently registered visitors
- Total parking spaces
- Available and reserved parking spaces
- Upcoming reservations
- Administrative warnings and operational issues

Information should be filterable by location and date.

**Important architectural requirement:**

Every displayed metric must have a clearly identified and technically supported data source.

Do not assume that workplace reservations, physical occupancy, and employee presence represent the same information.

Where Microsoft Places does not expose the required information through supported APIs, document the limitation and evaluate realistic alternatives.

### 4.2 Microsoft Places Structure Management

PlaceHub should provide simplified management of the Microsoft Places location hierarchy.

The intended business hierarchy is:

**Building → Floor → Section → Desk Pool / Desk**

Required capabilities to investigate include:

- List buildings
- Create and update buildings
- Manage floors
- Manage sections
- Create desk pools
- Update desk pools
- Manage workspace capacity
- Associate workplaces with areas
- Import or synchronize existing Places structures
- Display related resources and booking information

The application must respect the actual Microsoft Places resource model.

In particular, investigate the relationships and distinctions between Sections, Workspaces, Desk Pools, and individual Desks.

Do not introduce a custom hierarchy that conflicts with the Microsoft Places data model.

Compare the capabilities of Microsoft Graph Places API, Microsoft Places PowerShell, and Exchange Online PowerShell where relevant.

For operations that cannot be performed using a supported API, design a documented administrative provisioning approach.

### 4.3 Visitor Management

Office Management should be able to register external visitors and schedule visits to managed locations.

Potential capabilities:

- Register visitors
- Specify visit date and time
- Select the destination building
- Assign an internal host
- Record the purpose of a visit
- Display daily visitor schedules
- Update or cancel visits
- Optionally support visitor check-in and check-out
- Optionally reserve parking for visitors

**Important architectural distinction:**

A physical visitor is not necessarily a Microsoft Entra B2B guest user.

First determine whether Microsoft Places exposes a suitable documented visitor-management integration.

If no appropriate native functionality exists, propose a lightweight visitor-management module within PlaceHub.

This module should store only the information required to manage physical visits and must not unnecessarily create Microsoft Entra guest accounts.

Consider GDPR requirements, data minimization, retention policies, and deletion procedures.

### 4.4 Parking Space Management

Parking management is an independent and important functional module.

**Fundamental technical assumption:**

Each parking space is represented in the background by a Microsoft Exchange Online resource mailbox.

These mailboxes provide the underlying calendar, availability, and booking functionality.

Office Management users should not need to know that resource mailboxes exist.

Instead, each parking space appears as a manageable business resource.

Example:

- Parking Space: P-017
- Building: Headquarters
- Location: Düsseldorf
- Area: Underground Garage
- Features: EV Charging
- Status: Available or Reserved
- Technical Resource: Associated Exchange Online mailbox

#### Administration Capabilities

- List parking spaces
- Create parking spaces
- Edit parking space information
- Disable parking spaces
- Associate parking spaces with buildings
- Assign categories and features
- Link Exchange resource mailboxes
- Import existing resource mailboxes
- Manage booking settings where technically supported

#### Booking Capabilities

- Check parking availability
- Reserve a parking space for a specified period
- Reserve parking for employees
- Reserve parking for visitors
- Display existing reservations
- Modify reservations
- Cancel reservations
- Prevent double bookings
- Display booking conflicts clearly

#### Architectural Requirements

Exchange Online must remain the authoritative source for actual calendar reservations.

A local database may contain additional parking metadata, but it must not create an independent booking system with conflicting reservation states.

Investigate:

- Room Mailboxes versus Equipment Mailboxes
- Automatic booking acceptance
- Exchange calendar processing
- Microsoft Graph Calendar APIs
- Microsoft Graph getSchedule
- Free/Busy queries
- Calendar events and meeting invitations
- Booking organizer identity
- Application versus Delegated Permissions
- Restricting application access to specific resource mailboxes
- Conflict detection and concurrent booking requests
- Recurring reservations
- Administrative provisioning of new resource mailboxes

Determine which operations are available through Microsoft Graph and which require Exchange Online administrative interfaces or PowerShell.

Evaluate whether creating resource mailboxes directly through PlaceHub is practical and secure.

Office Management users must not require permanently elevated Exchange administrator privileges.

### 4.5 Daily Operations Overview

Provide a location-specific daily operational view containing:

- Expected visitors
- Parking reservations
- Workplace or desk pool reservations, where supported
- Available capacity
- Upcoming bookings
- Operational exceptions

A calendar or timeline-based interface may be used if it improves usability.

---

## 5. Technical Architecture

The required technology baseline is **.NET 10 LTS**.

The preferred foundation is a maintainable ASP.NET Core application.

Evaluate the following architectural options:

1. ASP.NET Core with Blazor Web App
2. ASP.NET Core Web API with a separate frontend
3. Modular Monolith with clearly defined business modules

Compare these options regarding development effort, maintainability, user experience, Microsoft 365 integration, security, deployment, testability, scalability, and overall complexity.

Prefer a Modular Monolith over microservices unless clear functional or operational requirements justify a distributed architecture.

### Proposed Business Modules

- Dashboard
- Places Management
- Visitor Management
- Parking Management
- Booking Management
- Microsoft 365 Integration
- Identity & Authorization
- Administration & Diagnostics

Module boundaries must be clearly defined.

Microsoft integrations should be encapsulated behind well-defined interfaces or adapters.

Core business logic must not depend directly on concrete Microsoft Graph SDK implementation classes.

### Persistence Strategy

Evaluate whether a dedicated application database is required.

Potential locally managed data includes:

- Parking space metadata
- Exchange mailbox associations
- Visitor and visit records
- Application configuration
- Audit information
- Integration and synchronization state

Avoid unnecessary duplication of Microsoft 365 master data.

Evaluate Entity Framework Core with SQL Server or PostgreSQL.

Any additional infrastructure component must have a clearly justified purpose.

---

## 6. Microsoft 365 Integration and Documentation

Official Microsoft documentation is the authoritative technical reference.

Use the connected documentation tool:

**$ms-doc-mcp**

Use this integration to research Microsoft Places, Microsoft Graph, Exchange Online, Microsoft Entra ID, and .NET.

### Documentation Rules

1. Research supported Microsoft APIs before making architectural decisions.
2. Prefer documented, generally available interfaces.
3. Verify API versions, permissions, and limitations.
4. Distinguish Microsoft Graph v1.0 from Beta APIs.
5. Validate licensing requirements.
6. Document technical dependencies and potential breaking changes.
7. Never invent Graph endpoints, permissions, or unsupported capabilities.
8. Reference official Microsoft documentation in relevant ADRs.
9. Mark assumptions requiring Proof of Concept validation.

Also evaluate whether existing Microsoft Places Management Portal functionality can be reused or complemented instead of reimplemented unnecessarily.

---

## 7. Security and Authorization

The application supports administrative business operations and must follow secure-by-design principles.

Requirements include:

- Microsoft Entra ID authentication
- Single Sign-On
- Role-based authorization
- Least-privilege access
- Protection of personal information
- Auditable administrative operations
- Secure access token handling
- No credentials or secrets in source code
- Certificate-based authentication or Managed Identity where appropriate
- Restricted access to Exchange resource mailboxes
- No unnecessary tenant-wide privileges

Explicitly distinguish between:

**Interactive Office Management operations**

and

**Privileged administrative provisioning operations.**

Evaluate separate execution contexts, administrative services, approval workflows, or restricted automation processes where appropriate.

---

## 8. Nonfunctional Requirements

### Simplicity

Avoid unnecessary architectural patterns, services, frameworks, and operational dependencies.

### Maintainability

Ensure clear responsibilities, understandable component boundaries, and loose coupling.

### Extensibility

Allow additional resource types to be introduced in future versions without redesigning the entire system.

### Reliability

Handle Microsoft API errors, timeouts, throttling, and temporary service unavailability.

### Consistency

Prevent local application state from conflicting with authoritative Microsoft 365 booking states.

### Usability

Provide a business-friendly interface without exposing unnecessary Microsoft 365 technical terminology.

### Observability

Implement structured logging, operational diagnostics, and traceable error conditions.

### Testability

Core business logic must be testable without access to production Microsoft 365 services.

---

# 9. Mandatory Engineering Process

Development must follow clearly defined phases.

## Phase 1 – Discovery and Technical Feasibility

Begin with a structured analysis of functional requirements.

Investigate:

- Capabilities natively supported by Microsoft Places
- Capabilities exposed through Microsoft Graph
- Operations requiring PowerShell
- Technical representation of desk pools
- Availability of central Office Management reporting
- Accessibility of booking information
- Visitor management integration options
- Parking resource modeling
- Licensing requirements
- Required permissions and administrative roles

Create a **Capability Matrix** containing:

| Capability | Microsoft System | Interface | Support Status | Risks | Recommendation |
|---|---|---|---|---|---|

Classify each capability as technically confirmed, partially supported, experimental, or unresolved.

Document outstanding questions and technical uncertainties.

**Deliverable:** Technical feasibility assessment with official Microsoft documentation references.

## Phase 2 – Architecture Decision Records

Before designing the final architecture, establish a structured ADR collection.

Use this template:

### ADR-XXX: Decision Title

**Status:** Proposed / Accepted / Superseded

**Context:** What technical or business problem needs to be addressed?

**Decision:** What solution is proposed?

**Alternatives:** Which realistic alternatives were evaluated?

**Rationale:** Why is this option preferred?

**Consequences:** What are the positive and negative implications?

**Risks:** What are the technical, organizational, and operational risks?

**References:** Links to official documentation.

**Validation:** Which assumptions require a Proof of Concept?

### Required ADRs

- ADR-001: Overall System Architecture
- ADR-002: Frontend Technology and UI Strategy
- ADR-003: Backend Architecture with .NET 10
- ADR-004: Microsoft Graph Integration Strategy
- ADR-005: Microsoft Places Data Model and Hierarchy
- ADR-006: Exchange Resource Mailboxes as Parking Resources
- ADR-007: Parking Reservations and Consistency
- ADR-008: Visitor Management and Data Storage
- ADR-009: Authentication and Authorization
- ADR-010: Database and Persistence Strategy
- ADR-011: Synchronization, Caching, and Data Refresh
- ADR-012: Error Handling, Resilience, and Observability
- ADR-013: Deployment and Hosting Strategy
- ADR-014: Testing Strategy
- ADR-015: Administrative Provisioning and Privileged Operations

Additional ADRs are allowed when meaningful architectural decisions are required.

Do not create ADRs for trivial implementation details.

**Deliverable:** Initial ADR collection.

## Phase 3 – Solution Architecture

Based on the proposed ADRs, create a concrete technical architecture.

Required artifacts:

1. System Context Diagram
2. Container Diagram
3. Component Diagram
4. Domain Model
5. Data Flow Diagrams
6. Microsoft 365 Integration Architecture
7. Authentication and Authorization Design
8. Database Model
9. Error Handling and Synchronization Design
10. Deployment Architecture

Use Mermaid diagrams where practical.

Create sequence diagrams for at least:

- Creating a building
- Creating a desk pool
- Registering a visitor
- Creating a parking resource
- Booking a parking space
- Canceling a parking reservation
- Loading dashboard information

Separate internal application operations from external Microsoft 365 operations.

Include failure scenarios and appropriate recovery or compensation mechanisms.

**Deliverable:** Documented Solution Architecture.

## Phase 4 – MVP Definition

Define a realistically deliverable Minimum Viable Product.

The initial MVP should contain as few features as possible while providing tangible operational value.

Prioritize:

1. Microsoft Entra ID authentication
2. Central dashboard
3. Display of existing Places buildings and hierarchies
4. Basic building and desk pool management
5. Parking space overview
6. Parking availability
7. Parking reservations
8. Basic visitor management

Categorize requirements into:

- Must-have
- Should-have
- Could-have
- Out of Scope

Define clear acceptance criteria.

Respect technical dependencies and findings from the feasibility assessment.

**Deliverable:** Approved MVP scope proposal.

## Phase 5 – Implementation Planning

Create an actionable engineering implementation roadmap.

Include:

- Proposed .NET Solution structure
- Project organization
- Recommended NuGet packages
- Architectural guidelines
- Module boundaries
- Interface contracts
- Domain and persistence models
- Microsoft integration adapters
- Testing strategy
- Implementation sequence
- Technical milestones
- Dependencies and risks

Break down the roadmap into small, verifiable engineering work items with clearly defined acceptance criteria.

Each milestone must identify its functional outcome and associated validation or testing requirements.

**Deliverable:** Implementation-ready engineering backlog.

## Phase 6 – Technical Proof of Concept

Validate the most critical Microsoft 365 integrations before full implementation.

At minimum:

- Read the Microsoft Places hierarchy
- Create or update a Microsoft Places object
- Locate an existing Exchange resource mailbox
- Query parking availability using Free/Busy
- Create a parking reservation
- Cancel a reservation
- Validate the permission model
- Document API limitations and error scenarios

All testing must take place in an appropriate test environment.

Do not modify production Microsoft 365 resources without explicit authorization.

**Deliverable:** Validated integration decisions and documented Proof of Concept results.

---

# 10. Proposed Repository and Documentation Structure

```text
/docs
  /architecture
    /adr
      ADR-001-system-architecture.md
      ADR-002-frontend.md
      ...
    system-context.md
    solution-architecture.md
    domain-model.md
    integration-architecture.md
    security-architecture.md

  /requirements
    functional-requirements.md
    non-functional-requirements.md
    capability-matrix.md

  /planning
    mvp-scope.md
    implementation-roadmap.md
    engineering-backlog.md

  /research
    microsoft-places.md
    microsoft-graph.md
    exchange-resources.md
    api-limitations.md

  /poc
    validation-plan.md
    validation-results.md

/src
  (Only after architecture approval)

/tests
  (Only after the testing strategy is defined)
```

This structure may be adjusted following a documented architectural decision.

---

# 11. Engineering Principles

### Architecture First

Do not begin implementation until the essential architecture decisions are documented and reviewed.

### Documentation Driven

Use official Microsoft documentation through **$ms-doc-mcp** as the primary reference.

### Pragmatic Engineering

Avoid unnecessary abstractions, microservices, and infrastructure complexity.

### Microsoft 365 Native

Use existing Microsoft 365 capabilities before building replacements.

### Security by Design

Address authorization, credentials, privileges, and data protection from the beginning.

### Explicit Trade-offs

Document the advantages, disadvantages, and implications of significant architectural choices.

### No Assumptions Presented as Facts

Never claim that an undocumented or unverified Microsoft API capability is available.

### Human Approval Gates

Pause at major architecture milestones and present decisions for technical or business review.

Do not independently start implementation, configure production systems, or modify Microsoft 365 resources without the required approval.

---

# 12. Initial Assignment

Start **Phase 1 and the preparation of Phase 2 only**.

Perform the following tasks:

1. Analyze the functional requirements and project scope.
2. Research Microsoft Places and Microsoft Graph APIs using **$ms-doc-mcp**.
3. Investigate the technical representation of buildings, floors, sections, workspaces, and desk pools.
4. Assess parking space management using Exchange Online resource mailboxes.
5. Investigate visitor management capabilities and limitations.
6. Identify critical Microsoft 365 integration risks.
7. Produce a Capability Matrix.
8. Recommend an initial high-level system architecture.
9. Create and prioritize the Architecture Decision Record index.
10. Draft the most important foundational ADRs with status `Proposed`.

### Required Output

Present the results in this order:

**A. Executive Summary**

Brief evaluation of the project and its technical feasibility.

**B. Microsoft 365 Capability Assessment**

Which capabilities are genuinely supported by Microsoft Places, Microsoft Graph, and Exchange Online?

**C. Target Domain Model**

Which business domains and components are required?

**D. Architecture Alternatives**

Comparison of realistic .NET 10 architecture options.

**E. Architecture Decision Record Index**

Prioritized list of ADRs and decisions required.

**F. Initial ADRs**

Detailed proposals for foundational architecture decisions.

**G. Risks and Open Questions**

Specific integration risks, technical uncertainties, and assumptions requiring validation.

**H. Recommended Next Steps**

Prioritized and manageable engineering work packages.

### Final Mandatory Instruction

**Do not generate application code, create database migrations, or perform production configuration changes until the architecture has been reviewed and the foundational ADRs have been approved.**

The objective is to design a professional, maintainable, secure, and deliberately lightweight Office Management application built on Microsoft Places, Exchange Online, and .NET 10 LTS.
